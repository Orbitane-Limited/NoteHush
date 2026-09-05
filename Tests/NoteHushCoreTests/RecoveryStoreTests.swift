import Darwin
import Foundation
import XCTest

@testable import NoteHushCore

@MainActor
final class RecoveryStoreTests: XCTestCase {
  func testSchemaOneMigratesToTwoKeepingOriginalGenerationAndFileBinding() async throws {
    let fixture = try RecoveryFixture()
    let original = fixture.snapshot(revision: 1, text: "legacy draft")
    try await fixture.store.commit(original)
    var envelope = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.primary)) as? [String: Any])
    envelope["version"] = 1
    let legacy = try JSONSerialization.data(withJSONObject: envelope)
    for name in [RecoveryStore.primaryName, RecoveryStore.previousName] {
      try legacy.write(to: fixture.directory.appending(path: name))
    }
    let loaded = try await fixture.store.load()
    XCTAssertEqual(loaded.snapshot, original)
    let document = fixture.directory.appending(path: "document.txt")
    let binding = try await TextFileService().save(
      "legacy draft", encoding: .utf8, to: document, expected: nil, saveAs: true)
    var next = original
    next.revision = 2
    next.tabs[0].file = binding
    try await fixture.store.commit(next)
    let updated = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.primary)) as? [String: Any])
    XCTAssertEqual(updated["version"] as? Int, 2)
    XCTAssertEqual(
      try Data(contentsOf: fixture.directory.appending(path: RecoveryStore.previousName)), legacy)
    let restored = try await fixture.store.load()
    XCTAssertEqual(restored.snapshot?.tabs[0].file, binding)
  }

  func testFirstLaunchIsDistinctFromCorruption() async throws {
    let fixture = try RecoveryFixture()
    let loaded = try await fixture.store.load()
    XCTAssertNil(loaded.snapshot)
    XCTAssertEqual(loaded.source, .newWorkspace)
    XCTAssertFalse(loaded.foundDamagedGeneration)
  }

  func testCheckpointRestoresAllTabsAndExactUnicodeBytes() async throws {
    let fixture = try RecoveryFixture()
    let first = TabSnapshot(text: "draft\r\n👩🏽‍💻")
    let second = TabSnapshot(
      text: "اردو e\u{301}", selection: TextSelection(location: 2, length: 1))
    let snapshot = WorkspaceSnapshot(revision: 1, tabs: [first, second], selectedTabID: second.id)
    try await fixture.store.commit(snapshot)
    let loaded = try await RecoveryStore(directory: fixture.directory).load()
    XCTAssertEqual(loaded.snapshot, snapshot)
    XCTAssertEqual(Array(try XCTUnwrap(loaded.snapshot).tabs[1].text.utf8), Array(second.text.utf8))
    XCTAssertEqual(loaded.source, .primary)
    let attributes = try FileManager.default.attributesOfItem(atPath: fixture.primary.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  func testCorruptPrimaryFallsBackAndIsPreservedBeforeNextCommit() async throws {
    let fixture = try RecoveryFixture()
    let first = fixture.snapshot(revision: 1, text: "older committed text")
    try await fixture.store.commit(first)
    try await fixture.store.commit(fixture.snapshot(revision: 2, text: "latest text"))
    let damaged = Data("truncated {".utf8)
    try damaged.write(to: fixture.primary)
    let loaded = try await fixture.store.load()
    XCTAssertEqual(loaded.snapshot, first)
    XCTAssertEqual(loaded.source, .previous)
    XCTAssertTrue(loaded.foundDamagedGeneration)
    let repaired = fixture.snapshot(revision: 3, text: "continued after recovery")
    try await fixture.store.commit(repaired)
    let names = try FileManager.default.contentsOfDirectory(
      at: fixture.directory, includingPropertiesForKeys: nil)
    let evidence = names.filter { $0.lastPathComponent.hasPrefix("damaged-") }
    XCTAssertEqual(evidence.count, 1)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(evidence.first)), damaged)
    let reloaded = try await fixture.store.load()
    XCTAssertEqual(reloaded.snapshot, repaired)
  }

  func testChecksumMismatchFallsBackInsteadOfAcceptingChangedPayload() async throws {
    let fixture = try RecoveryFixture()
    let snapshot = fixture.snapshot(revision: 1, text: "recover this")
    try await fixture.store.commit(snapshot)
    var envelope = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.primary)) as? [String: Any])
    envelope["sha256"] = "incorrect"
    try JSONSerialization.data(withJSONObject: envelope).write(to: fixture.primary)
    let loaded = try await fixture.store.load()
    XCTAssertEqual(loaded.snapshot, snapshot)
    XCTAssertEqual(loaded.source, .previous)
  }

  func testMissingPrimaryUsesBackupRatherThanCreatingEmptyWorkspace() async throws {
    let fixture = try RecoveryFixture()
    let snapshot = fixture.snapshot(revision: 1, text: "only backup remains")
    try await fixture.store.commit(snapshot)
    try FileManager.default.removeItem(at: fixture.primary)
    let loaded = try await fixture.store.load()
    XCTAssertEqual(loaded.snapshot, snapshot)
    XCTAssertEqual(loaded.source, .previous)
  }

  func testUnknownSchemaInEitherGenerationBlocksReadsAndWrites() async throws {
    for name in [RecoveryStore.primaryName, RecoveryStore.previousName] {
      let fixture = try RecoveryFixture()
      try await fixture.store.commit(fixture.snapshot(revision: 1, text: "original"))
      let future = Data("{\"version\":999,\"futureStructure\":true}".utf8)
      let path = fixture.directory.appendingPathComponent(name)
      try future.write(to: path)
      do {
        _ = try await fixture.store.load()
        XCTFail("A future schema must not silently fall back")
      } catch { XCTAssertEqual(error as? RecoveryError, .unsupportedSchema(999)) }
      do {
        try await fixture.store.commit(fixture.snapshot(revision: 2, text: "must not overwrite"))
        XCTFail("A downgraded app must not overwrite future recovery data")
      } catch { XCTAssertEqual(error as? RecoveryError, .unsupportedSchema(999)) }
      XCTAssertEqual(try Data(contentsOf: path), future)
    }
  }

  func testAllCorruptGenerationsAreRetainedAndNeverResetToEmpty() async throws {
    let fixture = try RecoveryFixture()
    try await fixture.store.commit(fixture.snapshot(revision: 1))
    let corrupt = Data("bad checkpoint".utf8)
    for name in [RecoveryStore.primaryName, RecoveryStore.previousName] {
      try corrupt.write(to: fixture.directory.appendingPathComponent(name))
    }
    do {
      _ = try await fixture.store.load()
      XCTFail("Corruption is not a new workspace")
    } catch { XCTAssertEqual(error as? RecoveryError, .corruptGenerations) }
    do {
      try await fixture.store.commit(fixture.snapshot(revision: 2))
      XCTFail("Existing evidence must be preserved")
    } catch { XCTAssertEqual(error as? RecoveryError, .corruptGenerations) }
    XCTAssertEqual(try Data(contentsOf: fixture.primary), corrupt)
  }

  func testFailedPrimaryWriteDoesNotAdvanceCommittedRevision() async throws {
    let fixture = try RecoveryFixture()
    let original = fixture.snapshot(revision: 1, text: "safe")
    try await fixture.store.commit(original)
    let failing = RecoveryStore(
      files: FaultingFiles(
        base: DiskRecoveryFiles(directory: fixture.directory),
        failedWrite: RecoveryStore.primaryName))
    let next = fixture.snapshot(revision: 2, text: "pending")
    do {
      try await failing.commit(next)
      XCTFail("A failed write must never report success")
    } catch { XCTAssertEqual(error as? RecoveryError, .storageUnavailable) }
    let loaded = try await fixture.store.load()
    XCTAssertEqual(loaded.snapshot, original)
    try await fixture.store.commit(next)
    let retried = try await fixture.store.load()
    XCTAssertEqual(retried.snapshot, next)
  }

  func testReadFailureIsNotInterpretedAsMissingData() async throws {
    let fixture = try RecoveryFixture()
    let failing = RecoveryStore(
      files: FaultingFiles(
        base: DiskRecoveryFiles(directory: fixture.directory),
        failedRead: RecoveryStore.primaryName))
    do {
      _ = try await failing.load()
      XCTFail("Permission errors must be visible")
    } catch { XCTAssertEqual(error as? RecoveryError, .storageUnavailable) }
  }

  func testFailedBackupPublicationLeavesTheLatestPrimaryUntouched() async throws {
    let fixture = try RecoveryFixture()
    try await fixture.store.commit(fixture.snapshot(revision: 1, text: "first"))
    let latest = fixture.snapshot(revision: 2, text: "latest")
    try await fixture.store.commit(latest)
    let before = try Data(contentsOf: fixture.primary)
    let failing = RecoveryStore(
      files: FaultingFiles(
        base: DiskRecoveryFiles(directory: fixture.directory),
        failedWrite: RecoveryStore.previousName))
    do {
      try await failing.commit(fixture.snapshot(revision: 3, text: "pending"))
      XCTFail("Primary publication must wait for a safe backup")
    } catch { XCTAssertEqual(error as? RecoveryError, .storageUnavailable) }
    XCTAssertEqual(try Data(contentsOf: fixture.primary), before)
    let loaded = try await fixture.store.load()
    XCTAssertEqual(loaded.snapshot, latest)
  }

  func testConflictingValidGenerationsAreNotSilentlyChosen() async throws {
    let fixture = try RecoveryFixture()
    let other = try RecoveryFixture()
    try await fixture.store.commit(fixture.snapshot(revision: 1, text: "one"))
    try await other.store.commit(other.snapshot(revision: 1, text: "different"))
    try Data(contentsOf: other.primary).write(
      to: fixture.directory.appendingPathComponent(RecoveryStore.previousName))
    do {
      _ = try await fixture.store.load()
      XCTFail("Two different valid states with one revision require recovery intervention")
    } catch { XCTAssertEqual(error as? RecoveryError, .conflictingRevision) }
  }

  func testStaleAndConflictingRevisionsCannotReplaceNewerText() async throws {
    let fixture = try RecoveryFixture()
    let original = fixture.snapshot(revision: 10, text: "latest")
    try await fixture.store.commit(original)
    for (revision, expected) in [
      (UInt64(9), RecoveryError.staleRevision), (10, .conflictingRevision),
    ] {
      do {
        try await fixture.store.commit(fixture.snapshot(revision: revision, text: "stale task"))
        XCTFail("Out-of-order work must not overwrite current content")
      } catch { XCTAssertEqual(error as? RecoveryError, expected) }
    }
    let unchanged = try await fixture.store.commit(original)
    XCTAssertEqual(unchanged, .unchanged)
    let loaded = try await fixture.store.load()
    XCTAssertEqual(loaded.snapshot, original)
  }

  func testCanonicalEquivalentStringsStillHaveDistinctBytesAtSameRevision() async throws {
    let fixture = try RecoveryFixture()
    let original = fixture.snapshot(revision: 1, text: "é")
    try await fixture.store.commit(original)
    var changed = original
    changed.tabs[0].text = "e\u{301}"
    XCTAssertEqual(changed.tabs[0].text, original.tabs[0].text)
    do {
      try await fixture.store.commit(changed)
      XCTFail("Byte changes cannot be hidden by Unicode canonical equality")
    } catch { XCTAssertEqual(error as? RecoveryError, .conflictingRevision) }
  }

  func testConcurrentCommitsKeepTheHighestRevision() async throws {
    let fixture = try RecoveryFixture()
    let store = fixture.store
    let original = fixture.snapshot(revision: 0)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for revision in 1...30 {
        group.addTask {
          var snapshot = original
          snapshot.revision = UInt64(revision)
          snapshot.tabs[0].text = "revision \(revision)"
          do {
            try await store.commit(snapshot)
          } catch RecoveryError.staleRevision {
            // A newer snapshot already committed.
          }
        }
      }
      try await group.waitForAll()
    }
    let loaded = try await store.load()
    XCTAssertEqual(loaded.snapshot?.revision, 30)
    XCTAssertEqual(loaded.snapshot?.tabs[0].text, "revision 30")
  }

  func testIndependentStoreRechecksDiskRevisionBeforeWriting() async throws {
    let fixture = try RecoveryFixture()
    let other = RecoveryStore(directory: fixture.directory)
    try await fixture.store.commit(fixture.snapshot(revision: 1))
    _ = try await fixture.store.load()
    try await other.commit(fixture.snapshot(revision: 3, text: "other writer"))
    do {
      try await fixture.store.commit(fixture.snapshot(revision: 2))
      XCTFail("A stale in-memory store must not overwrite the newer disk checkpoint")
    } catch { XCTAssertEqual(error as? RecoveryError, .staleRevision) }
  }

  func testHeldDiskLockFailsWithoutBlockingOrChangingFiles() async throws {
    let fixture = try RecoveryFixture()
    _ = try await fixture.store.load()
    let descriptor = open(fixture.directory.appendingPathComponent(".lock").path, O_RDWR)
    XCTAssertGreaterThanOrEqual(descriptor, 0)
    guard descriptor >= 0 else { return }
    defer {
      _ = flock(descriptor, LOCK_UN)
      close(descriptor)
    }
    XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
    do {
      try await fixture.store.commit(fixture.snapshot(revision: 1))
      XCTFail("The exclusive writer lock must be respected")
    } catch { XCTAssertEqual(error as? RecoveryError, .busy) }
  }

  func testInvalidSnapshotLeavesExistingCheckpointUntouched() async throws {
    let fixture = try RecoveryFixture()
    let original = fixture.snapshot(revision: 1)
    try await fixture.store.commit(original)
    var invalid = original
    invalid.revision = 2
    invalid.selectedTabID = UUID()
    do {
      try await fixture.store.commit(invalid)
      XCTFail("Invalid state must not be persisted")
    } catch { XCTAssertEqual(error as? WorkspaceValidationError, .missingSelectedTab) }
    let loaded = try await fixture.store.load()
    XCTAssertEqual(loaded.snapshot, original)
  }
}

private final class RecoveryFixture {
  let directory: URL
  let store: RecoveryStore
  private let tabID = UUID()
  var primary: URL { directory.appendingPathComponent(RecoveryStore.primaryName) }

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NoteHushTests-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    store = RecoveryStore(directory: directory)
  }

  func snapshot(revision: UInt64, text: String = "") -> WorkspaceSnapshot {
    WorkspaceSnapshot(
      revision: revision, tabs: [TabSnapshot(id: tabID, text: text)], selectedTabID: tabID)
  }

  deinit { try? FileManager.default.removeItem(at: directory) }
}

private struct FaultingFiles: RecoveryFiles {
  let base: DiskRecoveryFiles
  var failedWrite: String? = nil
  var failedRead: String? = nil

  func read(_ name: String) throws -> Data? {
    if name == failedRead { throw RecoveryError.storageUnavailable }
    return try base.read(name)
  }

  func writeAtomically(_ data: Data, named name: String) throws {
    if name == failedWrite { throw RecoveryError.storageUnavailable }
    try base.writeAtomically(data, named: name)
  }

  func withExclusiveAccess<T>(_ operation: () throws -> T) throws -> T {
    try base.withExclusiveAccess(operation)
  }
}
