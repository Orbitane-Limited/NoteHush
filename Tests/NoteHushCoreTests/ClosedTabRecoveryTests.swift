import Foundation
import XCTest

@testable import NoteHushCore

@MainActor
final class ClosedTabRecoveryTests: XCTestCase {
  func testSchemaFourMigratesHistoryAndPreservesRawBackup() async throws {
    let fixture = try RecoveryFixture()
    let original = fixture.snapshot(revision: 1, text: "open\r\n👩🏽‍💻")
    try await fixture.store.commit(original)
    var envelope = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.primary)) as? [String: Any])
    envelope["version"] = 4
    let legacy = try JSONSerialization.data(withJSONObject: envelope)
    for name in [RecoveryStore.primaryName, RecoveryStore.previousName] {
      try legacy.write(to: fixture.directory.appending(path: name))
    }
    let loaded = try await fixture.store.load()
    XCTAssertNil(loaded.snapshot?.closedTabs)
    var next = original
    next.revision = 2
    next.closedTabs = [
      ClosedTabSnapshot(
        tab: TabSnapshot(
          text: "اردو e\u{301}", selection: TextSelection(location: 2, length: 1),
          scroll: TextScrollPosition(anchor: 0, offset: 3)), originalIndex: Int.max)
    ]
    try await fixture.store.commit(next)
    let restored = try await fixture.store.load()
    XCTAssertEqual(restored.snapshot, next)
    XCTAssertEqual(
      try Data(contentsOf: fixture.directory.appending(path: RecoveryStore.previousName)), legacy)
  }

  func testInvalidHistoryCannotOverwriteValidWorkspace() async throws {
    let fixture = try RecoveryFixture()
    let original = fixture.snapshot(revision: 1)
    try await fixture.store.commit(original)
    let valid = ClosedTabSnapshot(tab: TabSnapshot(text: "closed"), originalIndex: 0)
    let histories = [
      [ClosedTabSnapshot(tab: original.tabs[0], originalIndex: 0)],
      [valid, valid],
      (0...20).map { _ in ClosedTabSnapshot(tab: TabSnapshot(), originalIndex: 0) },
      [ClosedTabSnapshot(tab: valid.tab, originalIndex: -1)],
      [
        ClosedTabSnapshot(
          tab: TabSnapshot(text: "hi", selection: TextSelection(location: 3)), originalIndex: 0)
      ],
    ]
    for history in histories {
      var next = original
      next.revision = 2
      next.closedTabs = history
      do {
        try await fixture.store.commit(next)
        XCTFail("Malformed closed history must not replace recoverable work")
      } catch { XCTAssertTrue(error is WorkspaceValidationError) }
    }
    let loaded = try await fixture.store.load()
    XCTAssertEqual(loaded.snapshot, original)
  }

  func testClearCompactsBothGenerationsAndKeepsOpenDrafts() async throws {
    let fixture = try RecoveryFixture()
    var original = fixture.snapshot(revision: 1, text: "keep open\r\nاردو")
    original.closedTabs = [ClosedTabSnapshot(tab: TabSnapshot(text: "clear me"), originalIndex: 0)]
    try await fixture.store.commit(original)
    var next = original
    next.revision = 2
    next.closedTabs = []
    try await fixture.store.commit(next)
    let previous = fixture.directory.appending(path: RecoveryStore.previousName)
    XCTAssertEqual(try Data(contentsOf: previous), try Data(contentsOf: fixture.primary))
    try Data("damaged".utf8).write(to: fixture.primary)
    let fallback = try await fixture.store.load()
    XCTAssertEqual(fallback.source, .previous)
    XCTAssertEqual(fallback.snapshot, next)
  }

  func testClearBeforePrimaryFailureRetainsHistoryAndRetryRemovesIt() async throws {
    let fixture = try RecoveryFixture()
    var original = fixture.snapshot(revision: 1, text: "keep open")
    original.closedTabs = [
      ClosedTabSnapshot(tab: TabSnapshot(text: "recoverable"), originalIndex: 0)
    ]
    try await fixture.store.commit(original)
    var next = original
    next.revision = 2
    next.closedTabs = []
    let failing = RecoveryStore(
      files: HistoryFailureFiles(
        base: DiskRecoveryFiles(directory: fixture.directory), afterPrimary: false))
    do {
      try await failing.commit(next)
      XCTFail("Failed primary write cannot clear history")
    } catch { XCTAssertEqual(error as? RecoveryError, .storageUnavailable) }
    let loaded = try await fixture.store.load()
    XCTAssertEqual(loaded.snapshot, original)
    try await fixture.store.commit(next)
    XCTAssertEqual(
      try Data(contentsOf: fixture.primary),
      try Data(contentsOf: fixture.directory.appending(path: RecoveryStore.previousName)))
  }

  func testInterruptedCleanupLoadsNewPrimaryAndSameRevisionRetryCompactsBackup() async throws {
    let fixture = try RecoveryFixture()
    var original = fixture.snapshot(revision: 1, text: "keep open")
    original.closedTabs = [ClosedTabSnapshot(tab: TabSnapshot(text: "clear me"), originalIndex: 0)]
    try await fixture.store.commit(original)
    var next = original
    next.revision = 2
    next.closedTabs = []
    let failing = RecoveryStore(
      files: HistoryFailureFiles(
        base: DiskRecoveryFiles(directory: fixture.directory), afterPrimary: true))
    do {
      try await failing.commit(next)
      XCTFail("Incomplete backup cleanup must report failure")
    } catch { XCTAssertEqual(error as? RecoveryError, .storageUnavailable) }
    let loaded = try await fixture.store.load()
    XCTAssertEqual(loaded.snapshot, next)
    let previous = fixture.directory.appending(path: RecoveryStore.previousName)
    XCTAssertNotEqual(try Data(contentsOf: previous), try Data(contentsOf: fixture.primary))
    let retry = try await fixture.store.commit(next)
    XCTAssertEqual(retry, .unchanged)
    XCTAssertEqual(try Data(contentsOf: previous), try Data(contentsOf: fixture.primary))
  }

  func testCoalescedCloseAndClearPrunesFormerlyOpenDraftFromBackup() async throws {
    let fixture = try RecoveryFixture()
    var original = fixture.snapshot(revision: 1, text: "keep")
    original.tabs.append(TabSnapshot(text: "closed then cleared before next write"))
    try await fixture.store.commit(original)
    var next = original
    next.revision = 2
    next.tabs.removeLast()
    next.closedTabs = []
    try await fixture.store.commit(next)
    XCTAssertEqual(
      try Data(contentsOf: fixture.primary),
      try Data(contentsOf: fixture.directory.appending(path: RecoveryStore.previousName)))
  }
}

private struct HistoryFailureFiles: RecoveryFiles {
  let base: DiskRecoveryFiles
  let afterPrimary: Bool
  func read(_ name: String) throws -> Data? { try base.read(name) }
  func withExclusiveAccess<T>(_ operation: () throws -> T) throws -> T {
    try base.withExclusiveAccess(operation)
  }
  func writeAtomically(_ data: Data, named name: String) throws {
    if !afterPrimary, name == RecoveryStore.primaryName { throw RecoveryError.storageUnavailable }
    if afterPrimary, name == RecoveryStore.previousName,
      let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let encoded = envelope["payload"] as? String, let payload = Data(base64Encoded: encoded),
      try JSONDecoder().decode(WorkspaceSnapshot.self, from: payload).revision == 2
    {
      // This failure occurs only in the cleanup write, after primary publication.
      XCTAssertEqual(try base.read(RecoveryStore.primaryName), data)
      throw RecoveryError.storageUnavailable
    }
    try base.writeAtomically(data, named: name)
  }
}
