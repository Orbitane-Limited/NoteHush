import Foundation

/// Injection boundary for slow or failed I/O. UI snapshots never perform disk work.
public protocol RecoveryWriting: Sendable {
  @discardableResult
  func commit(_ snapshot: WorkspaceSnapshot) async throws -> RecoveryCommit
}

extension RecoveryStore: RecoveryWriting {}

/// One in-flight write plus the latest pending snapshot. Cancelling a debounce
/// never cancels a write, and shutdown waits for both the active and final write.
@MainActor
public final class CheckpointCoordinator {
  private let store: any RecoveryWriting
  private let snapshot: @MainActor () -> WorkspaceSnapshot
  private let report: @MainActor (RecoveryError?) -> Void
  private let sleep: (@Sendable (Duration) async throws -> Void)?
  private var debounce: Task<Void, Never>?
  private var maximumDelay: Task<Void, Never>?
  private var writer: Task<Void, Never>?
  private var pending: WorkspaceSnapshot?
  private var stopping = false

  public init(
    store: any RecoveryWriting,
    snapshot: @escaping @MainActor () -> WorkspaceSnapshot,
    report: @escaping @MainActor (RecoveryError?) -> Void,
    sleep: (@Sendable (Duration) async throws -> Void)? = nil
  ) {
    self.store = store
    self.snapshot = snapshot
    self.report = report
    self.sleep = sleep
  }

  public func changed(immediate: Bool = false) {
    guard !stopping else { return }
    if immediate {
      checkpoint()
      return
    }
    debounce?.cancel()
    debounce = timer(after: .milliseconds(250))
    if maximumDelay == nil {
      maximumDelay = timer(after: .milliseconds(500))
    }
  }

  public func retry() {
    guard !stopping else { return }
    checkpoint()
  }

  public func shutdown() async {
    if !stopping {
      stopping = true
      checkpoint()
    }
    await writer?.value
  }

  private func timer(after duration: Duration) -> Task<Void, Never> {
    Task { [weak self, sleep] in
      do {
        if let sleep {
          try await sleep(duration)
        } else {
          // Keep the real timer here: invoking an async default-argument
          // closure from a linked client crashes on the supported toolchain.
          // The continuous-input child harness exercises this production path.
          try await Task.sleep(for: duration)
        }
        try Task.checkCancellation()
        self?.checkpoint()
      } catch {
        // Replaced timer or completed shutdown; an in-flight write is unaffected.
      }
    }
  }

  private func checkpoint() {
    debounce?.cancel()
    maximumDelay?.cancel()
    debounce = nil
    maximumDelay = nil
    pending = snapshot()
    guard writer == nil else { return }
    writer = Task { [weak self] in
      guard let self else { return }
      while let next = pending {
        pending = nil
        do {
          try await store.commit(next)
          report(nil)
        } catch {
          report(error as? RecoveryError ?? .storageUnavailable)
        }
      }
      writer = nil
    }
  }
}
