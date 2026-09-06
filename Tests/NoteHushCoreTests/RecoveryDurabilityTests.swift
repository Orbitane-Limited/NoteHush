import Foundation
import XCTest

@testable import NoteHushCore

@MainActor
final class RecoveryDurabilityTests: XCTestCase {
  func testRetryCannotAcknowledgeRenamedCheckpointWhileDirectorySyncStillFails() async throws {
    let fixture = try RecoveryFixture()
    let original = fixture.snapshot(revision: 1, text: "previous checkpoint")
    try await fixture.store.commit(original)
    let next = fixture.snapshot(revision: 2, text: "pending durable checkpoint 👩🏽‍💻")
    let failing = RecoveryStore(files: UnsynchronizedFiles(directory: fixture.directory))
    do {
      try await failing.commit(next)
      XCTFail("A rename alone cannot acknowledge a durable checkpoint")
    } catch { XCTAssertEqual(error as? RecoveryError, .storageUnavailable) }
    // A reader can see the rename even though its durability was not confirmed.
    let visible = try await fixture.store.load()
    XCTAssertEqual(visible.snapshot, next)
    let primary = try Data(contentsOf: fixture.primary)
    let previous = try Data(
      contentsOf: fixture.directory.appending(path: RecoveryStore.previousName))
    do {
      try await failing.commit(next)
      XCTFail("An identical retry must not report success while durability still fails")
    } catch { XCTAssertEqual(error as? RecoveryError, .storageUnavailable) }
    XCTAssertEqual(try Data(contentsOf: fixture.primary), primary)
    XCTAssertEqual(
      try Data(contentsOf: fixture.directory.appending(path: RecoveryStore.previousName)), previous)
    let retried = try await fixture.store.commit(next)
    XCTAssertEqual(retried, .unchanged)
    let restored = try await fixture.store.load()
    XCTAssertEqual(restored.snapshot, next)
  }

  func testFailureAtEachPublicationPhaseNeverReportsSuccessOrLoadsPartialText() async throws {
    for name in [RecoveryStore.previousName, RecoveryStore.primaryName] {
      for phase in RecoveryWritePhase.allCases {
        let fixture = try RecoveryFixture()
        let original = fixture.snapshot(revision: 1, text: "previous\r\nاردو")
        try await fixture.store.commit(original)
        let next = fixture.snapshot(revision: 2, text: "latest e\u{301} 👩🏽‍💻\r\n")
        let files = DiskRecoveryFiles(directory: fixture.directory) { writtenName, writtenPhase in
          if writtenName == name && writtenPhase == phase { throw RecoveryError.storageUnavailable }
        }
        do {
          try await RecoveryStore(files: files).commit(next)
          XCTFail("An injected I/O failure must not report successful persistence")
        } catch { XCTAssertEqual(error as? RecoveryError, .storageUnavailable) }
        let loaded = try await fixture.store.load()
        let installed =
          name == RecoveryStore.primaryName
          && (phase == .renamed || phase == .directorySynchronized)
        let expected = installed ? next : original
        XCTAssertEqual(loaded.snapshot, expected)
        XCTAssertEqual(
          Array(try XCTUnwrap(loaded.snapshot).tabs[0].text.utf8), Array(expected.tabs[0].text.utf8)
        )
        try await fixture.store.commit(next)
        let restored = try await fixture.store.load()
        XCTAssertEqual(restored.snapshot, next)
      }
    }
  }
}

private struct UnsynchronizedFiles: RecoveryFiles {
  let base: DiskRecoveryFiles

  init(directory: URL) {
    base = DiskRecoveryFiles(directory: directory) { name, phase in
      if name == RecoveryStore.primaryName && phase == .renamed {
        throw RecoveryError.storageUnavailable
      }
    }
  }

  func read(_ name: String) throws -> Data? { try base.read(name) }
  func writeAtomically(_ data: Data, named name: String) throws {
    try base.writeAtomically(data, named: name)
  }
  func synchronizeDirectory() throws { throw RecoveryError.storageUnavailable }
  func withExclusiveAccess<T>(_ operation: () throws -> T) throws -> T {
    try base.withExclusiveAccess(operation)
  }
}
