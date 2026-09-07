import AppKit
import XCTest
import os

@testable import NoteHushCore

@MainActor
final class RecoveryWorkspaceTests: XCTestCase {
  func testFallbackWarningAndDamagedEvidenceSurviveEditingAndQuit() async throws {
    _ = NSApplication.shared
    let root = try fixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = RecoveryStore(directory: root)
    var seed = WorkspaceSnapshot.empty()
    seed.revision = 1
    seed.tabs[0].text = "recover e\u{301} 👩🏽‍💻\r\nاردو"
    try await store.commit(seed)
    let damaged = Data("truncated primary {".utf8)
    try damaged.write(to: root.appending(path: "session.json"))
    let workspace = WorkspaceWindowController(directory: root)
    await workspace.waitUntilLoaded()
    let editor = try XCTUnwrap(workspace.selectedTab?.editor)
    XCTAssertEqual(Array(editor.string.utf8), Array(seed.tabs[0].text.utf8))
    XCTAssertTrue(editor.isEditable)
    let message = try recoveryMessage(workspace)
    XCTAssertTrue(message.stringValue.contains("A recovery copy was used"))
    XCTAssertFalse(message.isHiddenOrHasHiddenAncestor)
    editor.insertText(
      " continued", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
    await workspace.prepareToQuit()
    XCTAssertTrue(message.stringValue.contains("A recovery copy was used"))
    workspace.close()
    let loaded = try await store.load()
    XCTAssertEqual(
      Array(try XCTUnwrap(loaded.snapshot).tabs[0].text.utf8), Array(editor.string.utf8))
    let evidence = try FileManager.default.contentsOfDirectory(
      at: root, includingPropertiesForKeys: nil
    )
    .filter {
      $0.lastPathComponent.hasPrefix("damaged-")
        && $0.lastPathComponent.hasSuffix("--session.json")
    }
    XCTAssertEqual(evidence.count, 1)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(evidence.first)), damaged)
  }

  func testUnreadableGenerationsStayReadOnlyAndRetryLoadsOnlyAfterRepair() async throws {
    _ = NSApplication.shared
    for futureSlot in ["session.json", "session.previous.json", "neither"] {
      let root = try fixtureDirectory()
      defer { try? FileManager.default.removeItem(at: root) }
      let store = RecoveryStore(directory: root)
      var seed = WorkspaceSnapshot.empty()
      seed.revision = 1
      seed.tabs[0].text = "retained fixture draft"
      try await store.commit(seed)
      let valid = try Data(contentsOf: root.appending(path: "session.json"))
      var originals: [String: Data] = [:]
      for name in ["session.json", "session.previous.json"] {
        let bytes =
          futureSlot == "neither"
          ? Data("broken \(name)".utf8)
          : (name == futureSlot ? Data("{\"version\":999,\"unrecognized\":true}".utf8) : valid)
        try bytes.write(to: root.appending(path: name))
        originals[name] = bytes
      }
      let workspace = WorkspaceWindowController(directory: root)
      await workspace.waitUntilLoaded()
      XCTAssertTrue(workspace.tabs.isEmpty)
      XCTAssertFalse(workspace.canEditFiles)
      let message = try recoveryMessage(workspace)
      XCTAssertTrue(message.stringValue.contains("Editing is disabled"))
      workspace.newTab(nil)
      XCTAssertTrue(workspace.tabs.isEmpty)
      try retryButton(workspace).performClick(nil)
      await workspace.waitUntilLoaded()
      XCTAssertTrue(workspace.tabs.isEmpty)
      for name in try FileManager.default.contentsOfDirectory(atPath: root.path)
      where name.hasPrefix("blob-") {
        originals[name] = try Data(contentsOf: root.appending(path: name))
      }
      let exported = try JSONDecoder().decode(
        [String: Data].self, from: await store.exportGenerations())
      XCTAssertEqual(exported, originals)
      await workspace.prepareToQuit()
      workspace.close()
      for (name, bytes) in originals {
        XCTAssertEqual(try Data(contentsOf: root.appending(path: name)), bytes)
      }
      let retried = WorkspaceWindowController(directory: root)
      await retried.waitUntilLoaded()
      XCTAssertFalse(retried.canEditFiles)
      // Repair only this generated fixture; Retry must actually reload it.
      for name in ["session.json", "session.previous.json"] {
        try valid.write(to: root.appending(path: name))
      }
      try retryButton(retried).performClick(nil)
      await retried.waitUntilLoaded()
      XCTAssertEqual(retried.selectedTab?.editor.string, seed.tabs[0].text)
      XCTAssertTrue(retried.canEditFiles)
      await retried.prepareToQuit()
      retried.close()
      let restored = try await store.load()
      XCTAssertEqual(restored.snapshot?.tabs[0].text, seed.tabs[0].text)
    }
  }

  func testWriteFailureLeavesEditableDraftAndSourceBytesUntilSuccessfulRetry() async throws {
    _ = NSApplication.shared
    let root = try fixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "source.txt")
    let binding = try await TextFileService().save(
      "original\r\nاردو", encoding: .utf16BE, to: source, expected: nil, saveAs: true)
    let sourceBytes = try Data(contentsOf: source)
    let tab = TabSnapshot(text: "original\r\nاردو", file: binding)
    let seed = WorkspaceSnapshot(revision: 1, tabs: [tab], selectedTabID: tab.id)
    let directory = root.appending(path: "Recovery")
    let store = RecoveryStore(directory: directory)
    try await store.commit(seed)
    let failing = OSAllocatedUnfairLock(initialState: true)
    let files = SwitchableRecoveryFiles(
      base: DiskRecoveryFiles(directory: directory), failing: failing)
    let workspace = WorkspaceWindowController(store: RecoveryStore(files: files))
    await workspace.waitUntilLoaded()
    let editor = try XCTUnwrap(workspace.selectedTab?.editor)
    let draft = "unsaved e\u{301} 👩🏽‍💻\r\n"
    editor.insertText(
      draft, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    let message = try recoveryMessage(workspace)
    let failed = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        MainActor.assumeIsolated {
          message.stringValue.contains("Draft recovery could not be saved")
        }
      }, object: nil)
    await fulfillment(of: [failed], timeout: 5)
    XCTAssertFalse(message.isHiddenOrHasHiddenAncestor)
    XCTAssertNil(workspace.window?.attachedSheet)
    XCTAssertTrue(editor.isEditable)
    let beforeRetry = try await store.load()
    XCTAssertEqual(beforeRetry.snapshot, seed)
    XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
    failing.withLock { $0 = false }
    try retryButton(workspace).performClick(nil)
    let saved = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        MainActor.assumeIsolated { message.isHiddenOrHasHiddenAncestor }
      }, object: nil)
    await fulfillment(of: [saved], timeout: 5)
    let afterRetry = try await store.load()
    XCTAssertEqual(Array(try XCTUnwrap(afterRetry.snapshot).tabs[0].text.utf8), Array(draft.utf8))
    XCTAssertEqual(afterRetry.snapshot?.tabs[0].file, binding)
    await workspace.prepareToQuit()
    workspace.close()
    XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
  }

  private func fixtureDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "NoteHushRecoveryUI-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  private func recoveryMessage(_ workspace: WorkspaceWindowController) throws -> NSTextField {
    let views = descendants(try XCTUnwrap(workspace.window?.contentView))
    return try XCTUnwrap(
      views.compactMap { $0 as? NSTextField }.first {
        $0.accessibilityIdentifier() == "recovery-message"
      })
  }

  private func retryButton(_ workspace: WorkspaceWindowController) throws -> NSButton {
    let views = descendants(try XCTUnwrap(workspace.window?.contentView))
    return try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "Retry" })
  }
}

private struct SwitchableRecoveryFiles: RecoveryFiles {
  let base: DiskRecoveryFiles
  let failing: OSAllocatedUnfairLock<Bool>
  func read(_ name: String) throws -> Data? { try base.read(name) }
  func writeAtomically(_ data: Data, named name: String) throws {
    if failing.withLock({ $0 }) { throw RecoveryError.storageUnavailable }
    try base.writeAtomically(data, named: name)
  }
  func synchronizeDirectory() throws {
    if failing.withLock({ $0 }) { throw RecoveryError.storageUnavailable }
    try base.synchronizeDirectory()
  }
  func fingerprint(_ name: String) throws -> RecoveryFileFingerprint? {
    try base.fingerprint(name)
  }
  func names() throws -> [String] { try base.names() }
  func remove(_ name: String) throws { try base.remove(name) }

  func withExclusiveAccess<T>(_ operation: () throws -> T) throws -> T {
    try base.withExclusiveAccess(operation)
  }
}
