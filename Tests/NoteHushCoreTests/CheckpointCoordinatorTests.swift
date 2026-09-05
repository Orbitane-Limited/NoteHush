import Foundation
import XCTest

@testable import NoteHushCore

@MainActor
final class CheckpointCoordinatorTests: XCTestCase {
  func testImmediateEditThenQuitFlushesWithoutWaitingForDebounce() async {
    let clock = TestCheckpointClock()
    let disk = TestCheckpointWriter()
    var snapshot = WorkspaceSnapshot.empty()
    let coordinator = CheckpointCoordinator(
      store: disk, snapshot: { snapshot }, report: { _ in }, sleep: clock.sleep)
    snapshot.revision = 1
    snapshot.tabs[0].text = "Last keystroke 📝"
    coordinator.changed()
    await coordinator.shutdown()
    let saved = await disk.saved
    XCTAssertEqual(saved, [snapshot])
    await clock.finish()
  }

  func testShutdownDrainsInFlightWriteAndLatestPendingSnapshotOnly() async {
    let disk = TestCheckpointWriter(blockFirst: true)
    var snapshot = WorkspaceSnapshot.empty()
    snapshot.revision = 1
    var captureCount = 0
    let capturedFinal = expectation(description: "Captured final snapshot")
    let coordinator = CheckpointCoordinator(
      store: disk,
      snapshot: {
        captureCount += 1
        if snapshot.revision == 3 { capturedFinal.fulfill() }
        return snapshot
      }, report: { _ in })
    coordinator.changed(immediate: true)
    await disk.waitForAttempt(1)
    snapshot.revision = 2
    snapshot.tabs[0].text = "Pending"
    coordinator.changed(immediate: true)
    snapshot.revision = 3
    snapshot.tabs[0].text = "Final edit"
    let firstQuit = Task { await coordinator.shutdown() }
    await fulfillment(of: [capturedFinal], timeout: 2)
    let secondQuit = Task { await coordinator.shutdown() }
    await disk.unblock()
    await firstQuit.value
    await secondQuit.value
    let saved = await disk.saved
    XCTAssertEqual(saved.map(\.revision), [1, 3])
    XCTAssertEqual(saved.last?.tabs[0].text, "Final edit")
    XCTAssertEqual(captureCount, 3)
    coordinator.changed(immediate: true)
    XCTAssertEqual(captureCount, 3, "Edits after shutdown must not schedule another write")
  }

  func testContinuousEditsUseMaximumDelayEvenWhenDebounceKeepsResetting() async {
    let clock = TestCheckpointClock()
    let disk = TestCheckpointWriter()
    var snapshot = WorkspaceSnapshot.empty()
    let coordinator = CheckpointCoordinator(
      store: disk, snapshot: { snapshot }, report: { _ in }, sleep: clock.sleep)
    coordinator.changed()
    await clock.waitForSchedules(2)
    for revision in 1...8 {
      snapshot.revision = UInt64(revision)
      coordinator.changed()
    }
    await clock.fire(.milliseconds(500))
    await disk.waitForAttempt(1)
    let attempts = await disk.attempts
    XCTAssertEqual(attempts.first?.revision, 8)
    await coordinator.shutdown()
    await clock.finish()
  }

  func testDebounceWritesAfterPause() async {
    let clock = TestCheckpointClock()
    let disk = TestCheckpointWriter()
    var snapshot = WorkspaceSnapshot.empty()
    snapshot.revision = 7
    let coordinator = CheckpointCoordinator(
      store: disk, snapshot: { snapshot }, report: { _ in }, sleep: clock.sleep)
    coordinator.changed()
    await clock.waitForSchedules(2)
    await clock.fire(.milliseconds(250))
    await disk.waitForAttempt(1)
    let attempts = await disk.attempts
    XCTAssertEqual(attempts.first, snapshot)
    await coordinator.shutdown()
    await clock.finish()
  }

  func testFailureIsReportedRetrySucceedsAndQuitDoesNotHangOnFailure() async {
    let disk = TestCheckpointWriter(fail: true)
    let snapshot = WorkspaceSnapshot.empty()
    let failure = expectation(description: "Nonmodal failure")
    let recovered = expectation(description: "Successful retry")
    var reports: [RecoveryError?] = []
    let coordinator = CheckpointCoordinator(
      store: disk, snapshot: { snapshot },
      report: {
        reports.append($0)
        if reports.count == 1 { failure.fulfill() }
        if reports.count == 2 { recovered.fulfill() }
      })
    coordinator.changed(immediate: true)
    await fulfillment(of: [failure], timeout: 2)
    XCTAssertEqual(reports[0], .storageUnavailable)
    await disk.setFailure(false)
    coordinator.retry()
    await fulfillment(of: [recovered], timeout: 2)
    XCTAssertNil(reports[1])
    await disk.setFailure(true)
    await coordinator.shutdown()
    XCTAssertEqual(reports.last, .some(.storageUnavailable))
  }
}

private actor TestCheckpointWriter: RecoveryWriting {
  var attempts: [WorkspaceSnapshot] = []
  var saved: [WorkspaceSnapshot] = []
  private var fail: Bool
  private let blockFirst: Bool
  private var gate: CheckedContinuation<Void, Never>?
  private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

  init(blockFirst: Bool = false, fail: Bool = false) {
    self.blockFirst = blockFirst
    self.fail = fail
  }

  func commit(_ snapshot: WorkspaceSnapshot) async throws -> RecoveryCommit {
    attempts.append(snapshot)
    if blockFirst && attempts.count == 1 {
      await withCheckedContinuation { continuation in
        gate = continuation
        notifyObservers()
      }
    } else {
      notifyObservers()
    }
    if fail { throw RecoveryError.storageUnavailable }
    saved.append(snapshot)
    return .saved
  }

  func waitForAttempt(_ count: Int) async {
    if attempts.count >= count { return }
    await withCheckedContinuation { observers.append((count, $0)) }
  }

  func unblock() {
    gate?.resume()
    gate = nil
  }
  func setFailure(_ value: Bool) { fail = value }

  private func notifyObservers() {
    let ready = observers.filter { $0.0 <= attempts.count }
    observers.removeAll { $0.0 <= attempts.count }
    for observer in ready { observer.1.resume() }
  }
}

private actor TestCheckpointClock {
  private var waits: [(Duration, CheckedContinuation<Void, Never>)] = []
  private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
  private var schedules = 0
  private var finished = false

  func sleep(_ duration: Duration) async throws {
    if finished { throw CancellationError() }
    await withCheckedContinuation { continuation in
      waits.append((duration, continuation))
      schedules += 1
      let ready = observers.filter { $0.0 <= schedules }
      observers.removeAll { $0.0 <= schedules }
      for observer in ready { observer.1.resume() }
    }
  }

  func waitForSchedules(_ count: Int) async {
    if schedules >= count { return }
    await withCheckedContinuation { observers.append((count, $0)) }
  }

  func fire(_ duration: Duration) {
    let ready = waits.filter { $0.0 == duration }
    waits.removeAll { $0.0 == duration }
    for waiter in ready { waiter.1.resume() }
  }

  func finish() {
    finished = true
    for waiter in waits { waiter.1.resume() }
    waits.removeAll()
  }
}
