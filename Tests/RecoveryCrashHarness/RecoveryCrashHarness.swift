import Foundation
import NoteHushCore

/// Test-only child process. Never included in the app or release archive.
@main
enum RecoveryCrashHarness {
  static func main() async throws {
    let arguments = CommandLine.arguments
    guard arguments.count >= 3 else { throw HarnessError.arguments }
    if arguments[1] == "phase-write" {
      try await PhaseCrashScenario.write(arguments)
      return
    }
    if arguments[1] == "phase-read" {
      guard arguments.count == 3 else { throw HarnessError.arguments }
      try await PhaseCrashScenario.read(URL(filePath: arguments[2]))
      return
    }
    guard arguments.count == 3 else { throw HarnessError.arguments }
    let store = RecoveryStore(directory: URL(filePath: arguments[2], directoryHint: .isDirectory))
    if arguments[1] == "continuous" {
      await writeContinuously(store)
    } else if arguments[1] == "write" {
      var workspace = WorkspaceSnapshot.empty()
      for revision in 1...1000 {
        workspace.revision = UInt64(revision)
        workspace.tabs[0].text = String(repeating: "revision:\(revision)\n", count: 8192)
        try await store.commit(workspace)
        FileHandle.standardOutput.write(Data("\(revision)\n".utf8))
      }
    } else if arguments[1] == "read" {
      guard let workspace = try await store.load().snapshot else { throw HarnessError.missing }
      try workspace.validate()
      let expected = String(repeating: "revision:\(workspace.revision)\n", count: 8192)
      guard workspace.tabs[0].text == expected else { throw HarnessError.partialSnapshot }
      FileHandle.standardOutput.write(Data("\(workspace.revision)\n".utf8))
    } else {
      throw HarnessError.arguments
    }
  }

  @MainActor
  private static func writeContinuously(_ store: RecoveryStore) async {
    var workspace = WorkspaceSnapshot.empty()
    let writer = AcknowledgingWriter(store: store)
    let coordinator = CheckpointCoordinator(
      store: writer, snapshot: { workspace },
      report: { error in
        if error != nil { exit(1) }
      })
    for revision in 1...1000 {
      workspace.revision = UInt64(revision)
      workspace.tabs[0].text = String(repeating: "revision:\(revision)\n", count: 8192)
      coordinator.changed()
      // This deliberately models uninterrupted input, rather than waiting for a
      // commit after each edit. The parent kills after an acknowledged checkpoint.
      try? await Task.sleep(for: .milliseconds(10))
    }
    await coordinator.shutdown()
  }

  private enum HarnessError: Error { case arguments, missing, partialSnapshot }
}

private actor AcknowledgingWriter: RecoveryWriting {
  let store: RecoveryStore

  init(store: RecoveryStore) { self.store = store }

  func commit(_ snapshot: WorkspaceSnapshot) async throws -> RecoveryCommit {
    let result = try await store.commit(snapshot)
    FileHandle.standardOutput.write(Data("\(snapshot.revision)\n".utf8))
    return result
  }
}
