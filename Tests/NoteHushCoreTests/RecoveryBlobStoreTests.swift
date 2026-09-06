import CryptoKit
import Darwin
import Foundation
import XCTest
import os

@testable import NoteHushCore

@MainActor
final class RecoveryBlobStoreTests: XCTestCase {
  func testSameRevisionRetryRestoresMissingManifestBeforeReclamation() async throws {
    for missing in [RecoveryStore.primaryName, RecoveryStore.previousName] {
      let fixture = try RecoveryFixture()
      let snapshot = fixture.snapshot(revision: 1, text: "acknowledged")
      try await fixture.store.commit(snapshot)
      try FileManager.default.removeItem(at: fixture.directory.appending(path: missing))
      let retried = try await fixture.store.commit(snapshot)
      XCTAssertEqual(retried, .saved)
      XCTAssertEqual(
        try Data(contentsOf: fixture.primary),
        try Data(contentsOf: fixture.directory.appending(path: RecoveryStore.previousName)))
      let loaded = try await fixture.store.load()
      XCTAssertEqual(loaded.snapshot, snapshot)
      XCTAssertEqual(loaded.source, .primary)
    }
  }

  func testSameRevisionPromotesNewerFallbackToPrimary() async throws {
    let fixture = try RecoveryFixture()
    try await fixture.store.commit(fixture.snapshot(revision: 1, text: "older"))
    let next = fixture.snapshot(revision: 2, text: "latest")
    try await fixture.store.commit(next)
    let previous = fixture.directory.appending(path: RecoveryStore.previousName)
    let older = try Data(contentsOf: previous)
    let latest = try Data(contentsOf: fixture.primary)
    try older.write(to: fixture.primary)
    try latest.write(to: previous)
    let fallback = try await fixture.store.load()
    XCTAssertEqual(fallback.source, .previous)
    XCTAssertEqual(fallback.snapshot, next)
    try await fixture.store.commit(next)
    XCTAssertEqual(try Data(contentsOf: fixture.primary), latest)
    let promoted = try await fixture.store.load()
    XCTAssertEqual(promoted.source, .primary)
    XCTAssertEqual(promoted.snapshot, next)
  }

  func testOversizedRawExportFailsBeforeReadingSparseContents() async throws {
    let fixture = try RecoveryFixture()
    for name in ["large-a", "large-b", "large-c"] {
      let url = fixture.directory.appending(path: name)
      XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
      let handle = try FileHandle(forWritingTo: url)
      try handle.truncate(atOffset: UInt64(RecoveryStore.maximumEnvelopeBytes))
      try handle.close()
    }
    let files = RecordingRecoveryFiles(base: DiskRecoveryFiles(directory: fixture.directory))
    do {
      _ = try await RecoveryStore(files: files).exportGenerations()
      XCTFail("An oversized export must fail before allocating its contents")
    } catch { XCTAssertEqual(error as? RecoveryError, .snapshotTooLarge) }
    XCTAssertEqual(files.accesses.withLock { $0.reads }, [])
    for name in ["large-a", "large-b", "large-c"] {
      XCTAssertEqual(try files.fingerprint(name)?.size, Int64(RecoveryStore.maximumEnvelopeBytes))
    }
  }

  func testMetadataAndOneTabEditsDoNotReadOrRewriteUnchangedText() async throws {
    let fixture = try RecoveryFixture()
    let io = RecordingRecoveryFiles(base: DiskRecoveryFiles(directory: fixture.directory))
    let store = RecoveryStore(files: io)
    let tabs = (0..<20).map { index in
      TabSnapshot(text: "\(index):" + String(repeating: "اردو e\u{301} 👩🏽‍💻\r\n", count: 2048))
    }
    var snapshot = WorkspaceSnapshot(revision: 1, tabs: tabs, selectedTabID: tabs[0].id)
    try await store.commit(snapshot)
    io.reset()
    snapshot.revision += 1
    snapshot.selectedTabID = tabs[1].id
    snapshot.tabs[1].selection = TextSelection(location: 3, length: 2)
    try await store.commit(snapshot)
    XCTAssertEqual(io.blobReads, [])
    XCTAssertEqual(io.blobWrites, [])
    XCTAssertEqual(Set(io.writes), [RecoveryStore.primaryName, RecoveryStore.previousName])
    io.reset()
    snapshot.revision += 1
    snapshot.tabs[1].text += "changed"
    try await store.commit(snapshot)
    XCTAssertEqual(io.blobReads, [])
    XCTAssertEqual(io.blobWrites.count, 1)
    let restored = try await RecoveryStore(directory: fixture.directory).load()
    XCTAssertEqual(restored.snapshot, snapshot)
    io.reset()
    let loaded = try await store.load()
    XCTAssertEqual(
      io.blobReads.count, 21, "Fresh load checks all distinct blobs in both generations")
    var recovered = try XCTUnwrap(loaded.snapshot)
    io.reset()
    recovered.revision += 1
    recovered.tabs[0].selection = TextSelection(location: 1)
    try await store.commit(recovered)
    XCTAssertEqual(io.blobReads, [])
    XCTAssertEqual(io.blobWrites, [])
  }

  func testChangedFingerprintInvalidatesWarmCacheAndPreservesCorruptBytes() async throws {
    let fixture = try RecoveryFixture()
    let first = fixture.snapshot(revision: 1, text: "older safe")
    try await fixture.store.commit(first)
    let latest = fixture.snapshot(revision: 2, text: "latest text")
    try await fixture.store.commit(latest)
    let name = try RecoveryBlobReference(text: latest.tabs[0].text).name(for: latest.tabs[0].id)
    let url = fixture.directory.appending(path: name)
    let priorDate = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]
    let corrupt = Data("broken text".utf8)  // Same byte count; restore mtime to exercise ctime too.
    try corrupt.write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: XCTUnwrap(priorDate)], ofItemAtPath: url.path)
    var next = latest
    next.revision = 3
    try await fixture.store.commit(next)
    let restored = try await fixture.store.load()
    XCTAssertEqual(restored.snapshot, next)
    let exported = try JSONDecoder().decode(
      [String: Data].self, from: await fixture.store.exportGenerations())
    XCTAssertTrue(exported.contains { $0.key.hasPrefix("damaged-") && $0.value == corrupt })
  }

  func testMissingBlobFallsBackAndBothIncompleteGenerationsBlockWrites() async throws {
    let fixture = try RecoveryFixture()
    let first = fixture.snapshot(revision: 1, text: "previous")
    let next = fixture.snapshot(revision: 2, text: "current")
    try await fixture.store.commit(first)
    try await fixture.store.commit(next)
    let nextName = try RecoveryBlobReference(text: next.tabs[0].text).name(for: next.tabs[0].id)
    try FileManager.default.removeItem(at: fixture.directory.appending(path: nextName))
    let fallback = try await fixture.store.load()
    XCTAssertEqual(fallback.source, .previous)
    XCTAssertEqual(fallback.snapshot, first)
    XCTAssertTrue(fallback.foundDamagedGeneration)
    let oldName = try RecoveryBlobReference(text: first.tabs[0].text).name(for: first.tabs[0].id)
    try FileManager.default.removeItem(at: fixture.directory.appending(path: oldName))
    let original = try await fixture.store.exportGenerations()
    do {
      _ = try await fixture.store.load()
      XCTFail("No complete generation remains")
    } catch { XCTAssertEqual(error as? RecoveryError, .corruptGenerations) }
    do {
      try await fixture.store.commit(fixture.snapshot(revision: 3))
      XCTFail("Cannot reset damaged recovery")
    } catch { XCTAssertEqual(error as? RecoveryError, .corruptGenerations) }
    let unchanged = try await fixture.store.exportGenerations()
    XCTAssertEqual(unchanged, original)
  }

  func testReclamationKeepsBothGenerationsAndFiniteDamagedBundle() async throws {
    let fixture = try RecoveryFixture()
    var snapshot = fixture.snapshot(revision: 1, text: "initial")
    try await fixture.store.commit(snapshot)
    let damaged = Data("malformed manifest".utf8)
    try damaged.write(to: fixture.primary)
    let initialBlobs = try blobBytes(fixture.directory)
    snapshot.revision = 2
    snapshot.tabs[0].text = "second"
    try await fixture.store.commit(snapshot)
    let evidence = try await fixture.store.exportGenerations()
    let entries = try JSONDecoder().decode([String: Data].self, from: evidence)
    let manifestName = try XCTUnwrap(entries.keys.first { $0.hasSuffix("--session.json") })
    let prefix = String(manifestName.dropLast("session.json".count))
    XCTAssertEqual(entries[manifestName], damaged)
    for (name, bytes) in initialBlobs { XCTAssertEqual(entries[prefix + name], bytes) }
    let evidenceNames = entries.keys.filter { $0.hasPrefix("damaged-") }
    try Data("unrelated".utf8).write(to: fixture.directory.appending(path: "blob-not-managed.utf8"))
    for revision in 3...10 {
      snapshot.revision = UInt64(revision)
      snapshot.tabs[0].text = "revision \(revision)"
      try await fixture.store.commit(snapshot)
      XCTAssertEqual(try blobBytes(fixture.directory).count, 2)
    }
    let final = try JSONDecoder().decode(
      [String: Data].self, from: await fixture.store.exportGenerations())
    for name in evidenceNames { XCTAssertEqual(final[name], entries[name]) }
    XCTAssertEqual(final["blob-not-managed.utf8"], Data("unrelated".utf8))
    let loaded = try await fixture.store.load()
    XCTAssertEqual(loaded.snapshot, snapshot)
  }

  func testRemovalFailureKeepsNewStateAndSameRevisionRetryFinishesDurably() async throws {
    for phase in RecoveryRemovalPhase.allCases {
      let fixture = try RecoveryFixture()
      var snapshot = fixture.snapshot(revision: 1, text: "open")
      snapshot.closedTabs = [ClosedTabSnapshot(tab: TabSnapshot(text: "closed"), originalIndex: 0)]
      try await fixture.store.commit(snapshot)
      snapshot.revision = 2
      snapshot.closedTabs = []
      let files = DiskRecoveryFiles(
        directory: fixture.directory,
        observeRemoval: { _, reached in
          if reached == phase { throw RecoveryError.storageUnavailable }
        }, observe: { _, _ in })
      do {
        try await RecoveryStore(files: files).commit(snapshot)
        XCTFail("Cleanup failure cannot acknowledge success")
      } catch { XCTAssertEqual(error as? RecoveryError, .storageUnavailable) }
      let loaded = try await fixture.store.load()
      XCTAssertEqual(loaded.snapshot, snapshot)
      let retried = try await fixture.store.commit(snapshot)
      XCTAssertEqual(retried, .unchanged)
      XCTAssertEqual(try blobBytes(fixture.directory).count, 1)
    }
  }

  func testEveryBlobPublicationFailureDuringLegacyMigrationRetainsRawLegacy() async throws {
    for phase in RecoveryWritePhase.allCases {
      let fixture = try RecoveryFixture()
      let original = fixture.snapshot(revision: 1, text: "legacy\r\n\u{FEFF}اردو")
      let raw = try legacyRecoveryEnvelope(original, version: 5)
      for name in [RecoveryStore.primaryName, RecoveryStore.previousName] {
        try raw.write(to: fixture.directory.appending(path: name))
      }
      var next = original
      next.revision = 2
      next.tabs[0].text += "next"
      let files = DiskRecoveryFiles(directory: fixture.directory) { name, reached in
        if RecoveryBlobReference.isManagedName(name), reached == phase {
          throw RecoveryError.storageUnavailable
        }
      }
      do {
        try await RecoveryStore(files: files).commit(next)
        XCTFail("Migration was interrupted")
      } catch { XCTAssertEqual(error as? RecoveryError, .storageUnavailable) }
      for name in [RecoveryStore.primaryName, RecoveryStore.previousName] {
        XCTAssertEqual(try Data(contentsOf: fixture.directory.appending(path: name)), raw)
      }
      let before = try await fixture.store.load()
      XCTAssertEqual(before.snapshot, original)
      try await fixture.store.commit(next)
      let after = try await fixture.store.load()
      XCTAssertEqual(after.snapshot, next)
      XCTAssertEqual(
        try Data(contentsOf: fixture.directory.appending(path: RecoveryStore.previousName)), raw)
    }
  }

  func testDiskBoundaryRejectsLinksSpecialFilesTraversalAndIncompleteExport() async throws {
    let fixture = try RecoveryFixture()
    try await fixture.store.commit(fixture.snapshot(revision: 1, text: "safe"))
    let files = DiskRecoveryFiles(directory: fixture.directory)
    for name in ["../outside", "/outside", ".", "..", "nul\u{0}suffix"] {
      XCTAssertThrowsError(try files.read(name))
      XCTAssertThrowsError(try files.fingerprint(name))
      XCTAssertThrowsError(try files.writeAtomically(Data(), named: name))
      XCTAssertThrowsError(try files.remove(name))
    }
    let link = fixture.directory.appending(path: "unexpected-link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.primary)
    XCTAssertThrowsError(try files.read("unexpected-link"))
    XCTAssertThrowsError(try files.fingerprint("unexpected-link"))
    do {
      _ = try await fixture.store.exportGenerations()
      XCTFail("Cannot claim an incomplete raw export")
    } catch { XCTAssertEqual(error as? RecoveryError, .storageUnavailable) }
    let fifo = fixture.directory.appending(path: "fifo")
    XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
    XCTAssertThrowsError(try files.read("fifo"))
    XCTAssertThrowsError(try files.fingerprint("fifo"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
    let loaded = try await fixture.store.load()
    XCTAssertEqual(loaded.snapshot?.tabs[0].text, "safe")
  }

  private func blobBytes(_ directory: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for name in try FileManager.default.contentsOfDirectory(atPath: directory.path)
    where RecoveryBlobReference.isManagedName(name) {
      result[name] = try Data(contentsOf: directory.appending(path: name))
    }
    return result
  }
}

private struct RecordingRecoveryFiles: RecoveryFiles {
  struct Accesses {
    var reads: [String] = []
    var writes: [String] = []
  }
  let base: DiskRecoveryFiles
  let accesses = OSAllocatedUnfairLock(initialState: Accesses())
  var writes: [String] { accesses.withLock { $0.writes } }
  var blobReads: [String] {
    accesses.withLock { $0.reads.filter(RecoveryBlobReference.isManagedName) }
  }
  var blobWrites: [String] { writes.filter(RecoveryBlobReference.isManagedName) }
  func reset() { accesses.withLock { $0 = Accesses() } }
  func read(_ name: String) throws -> Data? {
    accesses.withLock { $0.reads.append(name) }
    return try base.read(name)
  }
  func writeAtomically(_ data: Data, named name: String) throws {
    accesses.withLock { $0.writes.append(name) }
    try base.writeAtomically(data, named: name)
  }
  func fingerprint(_ name: String) throws -> RecoveryFileFingerprint? { try base.fingerprint(name) }
  func names() throws -> [String] { try base.names() }
  func remove(_ name: String) throws { try base.remove(name) }
  func synchronizeDirectory() throws { try base.synchronizeDirectory() }
  func withExclusiveAccess<T>(_ operation: () throws -> T) throws -> T {
    try base.withExclusiveAccess(operation)
  }
}
