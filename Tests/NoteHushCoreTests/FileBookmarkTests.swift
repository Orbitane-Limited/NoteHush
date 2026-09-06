import Foundation
import XCTest
import os

@testable import NoteHushCore

@MainActor
final class FileBookmarkTests: XCTestCase {
  func testMovedStaleBookmarkRefreshesAuthorityWithoutAcceptingExternalEdits() async throws {
    let fixture = try BookmarkFixture()
    let bookmarks = ControlledBookmarks(url: fixture.url)
    let service = TextFileService(bookmarks: bookmarks)
    let original = try await service.open(fixture.url).binding
    let moved = fixture.directory.appending(path: "renamed.txt")
    try FileManager.default.moveItem(at: fixture.url, to: moved)
    try Data("external version".utf8).write(to: moved, options: .atomic)
    bookmarks.state.withLock {
      $0.url = moved
      $0.stale = true
    }
    let located = try await service.locate(original, grantedURL: nil)
    XCTAssertEqual(located.scopedURL, moved)
    XCTAssertEqual(located.binding.url, moved.standardizedFileURL)
    XCTAssertNotEqual(located.binding.bookmark, original.bookmark)
    XCTAssertEqual(located.binding.fileDigest, original.fileDigest)
    XCTAssertEqual(located.binding.identity, original.identity)
    do {
      _ = try await service.save(
        "draft", encoding: .utf8, to: located.scopedURL,
        expected: located.binding)
      XCTFail("Refreshing permission must not accept external changes")
    } catch { XCTAssertEqual(error as? TextFileError, .changedOnDisk) }
    XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "external version")
    bookmarks.assertBalanced()
  }

  func testRevokedBookmarkDoesNotFallBackToRememberedOrLivePath() async throws {
    let fixture = try BookmarkFixture()
    let bookmarks = ControlledBookmarks(url: fixture.url)
    let service = TextFileService(bookmarks: bookmarks)
    let original = try await service.open(fixture.url).binding
    bookmarks.state.withLock { $0.allowAccess = false }
    do {
      _ = try await service.locate(original, grantedURL: fixture.url)
      XCTFail("A revoked bookmark must require a new user grant")
    } catch { XCTAssertEqual(error as? TextFileError, .unavailable) }
    let counts = bookmarks.state.withLock { ($0.starts, $0.stops) }
    XCTAssertEqual(counts.0, 2)
    XCTAssertEqual(counts.1, 1, "Do not stop an access that failed to start")
  }

  func testUnavailableVolumeAndDeletedFileBalanceScopes() async throws {
    let fixture = try BookmarkFixture()
    let bookmarks = ControlledBookmarks(url: fixture.url)
    let service = TextFileService(bookmarks: bookmarks)
    let original = try await service.open(fixture.url).binding
    bookmarks.state.withLock { $0.failResolution = true }
    do {
      _ = try await service.locate(original, grantedURL: nil)
      XCTFail("Unavailable volume resolution must fail")
    } catch { XCTAssertEqual(error as? TextFileError, .unavailable) }
    bookmarks.state.withLock { $0.failResolution = false }
    try FileManager.default.removeItem(at: fixture.url)
    do {
      _ = try await service.locate(original, grantedURL: nil)
      XCTFail("Deleted file must not be recreated")
    } catch { XCTAssertEqual(error as? TextFileError, .unavailable) }
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url.path))
    bookmarks.assertBalanced()
  }

  func testLegacyPathRequiresFreshAuthorityAndCanThenGainBookmark() async throws {
    let fixture = try BookmarkFixture()
    let bookmarks = ControlledBookmarks(url: fixture.url)
    let service = TextFileService(bookmarks: bookmarks)
    let original = try await service.open(fixture.url).binding
    let legacy = original.relocating(to: fixture.url, bookmark: nil)
    do {
      _ = try await service.locate(legacy, grantedURL: nil)
      XCTFail("A stored path is not permission")
    } catch { XCTAssertEqual(error as? TextFileError, .unavailable) }
    let granted = try await service.locate(legacy, grantedURL: fixture.url)
    XCTAssertNotNil(granted.binding.bookmark)
    XCTAssertEqual(granted.binding.fileDigest, legacy.fileDigest)
    bookmarks.assertBalanced()
  }

  func testBookmarkCreationFailureDoesNotMisreportCompletedPublication() async throws {
    let fixture = try BookmarkFixture()
    let bookmarks = ControlledBookmarks(url: fixture.url)
    let service = TextFileService(bookmarks: bookmarks)
    let original = try await service.open(fixture.url).binding
    bookmarks.state.withLock { $0.failCreation = true }
    let saved = try await service.save(
      "saved", encoding: .utf8, to: fixture.url, expected: original)
    XCTAssertNil(saved.bookmark)
    XCTAssertEqual(saved.textDigest, TextDocumentCodec.textDigest("saved"))
    XCTAssertEqual(try String(contentsOf: fixture.url, encoding: .utf8), "saved")
    bookmarks.assertBalanced()
  }

  func testExplicitOverwriteStillRejectsASecondExternalChange() async throws {
    let fixture = try BookmarkFixture()
    let service = TextFileService()
    try Data("reviewed version".utf8).write(to: fixture.url, options: .atomic)
    let reviewed = try await service.open(fixture.url).binding
    try Data("newer version".utf8).write(to: fixture.url, options: .atomic)
    do {
      _ = try await service.save("draft", encoding: .utf8, to: fixture.url, expected: reviewed)
      XCTFail("Overwrite approval belongs only to the version that was reviewed")
    } catch { XCTAssertEqual(error as? TextFileError, .changedOnDisk) }
    XCTAssertEqual(try String(contentsOf: fixture.url, encoding: .utf8), "newer version")
    let latest = try await service.open(fixture.url).binding
    _ = try await service.save("draft", encoding: .utf8, to: fixture.url, expected: latest)
    XCTAssertEqual(try String(contentsOf: fixture.url, encoding: .utf8), "draft")
  }

  func testFailedDecodeAndPublicationReleaseAccess() async throws {
    let fixture = try BookmarkFixture()
    let bookmarks = ControlledBookmarks(url: fixture.url)
    let service = TextFileService(publisher: DeniedBookmarkPublication(), bookmarks: bookmarks)
    let original = try await service.open(fixture.url).binding
    do {
      _ = try await service.save("draft", encoding: .utf8, to: fixture.url, expected: original)
      XCTFail("Publication failure must surface")
    } catch { XCTAssertEqual(error as? TextFileError, .unavailable) }
    bookmarks.assertBalanced()
    try Data([0xFF]).write(to: fixture.url)
    do {
      _ = try await service.open(fixture.url)
      XCTFail("Invalid encoding must surface")
    } catch { XCTAssertEqual(error as? TextFileError, .invalidEncoding) }
    bookmarks.assertBalanced()
  }

  func testSchemaTwoUpgradesWithoutLosingLegacyGenerationOrBookmark() async throws {
    let fixture = try BookmarkFixture()
    let service = TextFileService(bookmarks: ControlledBookmarks(url: fixture.url))
    let binding = try await service.open(fixture.url).binding
    let legacy = binding.relocating(to: fixture.url, bookmark: nil)
    let store = RecoveryStore(directory: fixture.directory.appending(path: "Recovery"))
    let tab = TabSnapshot(text: "draft", file: legacy)
    var snapshot = WorkspaceSnapshot(revision: 1, tabs: [tab], selectedTabID: tab.id)
    let recovery = fixture.directory.appending(path: "Recovery")
    try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
    let raw = try legacyRecoveryEnvelope(snapshot, version: 2)
    for name in [RecoveryStore.primaryName, RecoveryStore.previousName] {
      try raw.write(to: recovery.appending(path: name))
    }
    let loaded = try await store.load()
    XCTAssertEqual(loaded.snapshot?.tabs[0].file, legacy)
    snapshot.revision = 2
    snapshot.tabs[0].file = binding
    try await store.commit(snapshot)
    let upgraded = try await store.load()
    XCTAssertEqual(upgraded.snapshot?.tabs[0].file?.bookmark, binding.bookmark)
    XCTAssertEqual(
      try Data(
        contentsOf: fixture.directory.appending(
          path:
            "Recovery/session.previous.json")), raw)
  }
}

private struct DeniedBookmarkPublication: TextFilePublishing {
  func publish(_ data: Data, to url: URL) throws { throw TextFileError.unavailable }
}

private struct ControlledBookmarks: FileBookmarking {
  struct State {
    var url: URL
    var stale = false
    var allowAccess = true
    var failCreation = false
    var failResolution = false
    var starts = 0
    var stops = 0
    var creations = 0
  }
  let state: OSAllocatedUnfairLock<State>
  init(url: URL) { state = OSAllocatedUnfairLock(initialState: State(url: url)) }
  func create(for url: URL) throws -> Data {
    try state.withLock {
      if $0.failCreation { throw TextFileError.unavailable }
      $0.creations += 1
      return Data("fixture-bookmark-\($0.creations)".utf8)
    }
  }
  func resolve(_ data: Data) throws -> ResolvedFileBookmark {
    try state.withLock {
      if $0.failResolution { throw TextFileError.unavailable }
      return ResolvedFileBookmark(url: $0.url, isStale: $0.stale)
    }
  }
  func startAccessing(_ url: URL) -> Bool {
    state.withLock {
      $0.starts += 1
      return $0.allowAccess
    }
  }
  func stopAccessing(_ url: URL) { state.withLock { $0.stops += 1 } }
  func assertBalanced(file: StaticString = #filePath, line: UInt = #line) {
    let counts = state.withLock { ($0.starts, $0.stops) }
    XCTAssertEqual(counts.0, counts.1, file: file, line: line)
  }
}

private final class BookmarkFixture {
  let directory = FileManager.default.temporaryDirectory.appending(
    path: "NoteHushBookmarks-\(UUID())")
  var url: URL { directory.appending(path: "original.txt") }
  init() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("original".utf8).write(to: url)
  }
  deinit { try? FileManager.default.removeItem(at: directory) }
}
