import AppKit
import XCTest

@testable import NoteHushCore

@MainActor
final class WorkspaceIntegrationTests: XCTestCase {
  func testFailedFinalWriteKeepsDraftAndShowsWarningWithoutBlockingQuit() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "NoteHushAppTests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = RecoveryStore(directory: directory)
    let seed = WorkspaceSnapshot.empty()
    try await store.commit(seed)
    let failedStore = RecoveryStore(
      files: UnwritableRecoveryFiles(base: DiskRecoveryFiles(directory: directory)))
    let controller = WorkspaceWindowController(store: failedStore)
    await controller.waitUntilLoaded()
    let tab = try XCTUnwrap(controller.tabs.first)
    tab.editor.insertText("Keep this draft", replacementRange: NSRange(location: 0, length: 0))
    await controller.prepareToQuit()
    XCTAssertEqual(tab.editor.string, "Keep this draft")
    let labels = allLabels(in: try XCTUnwrap(controller.window?.contentView))
    XCTAssertTrue(labels.contains { $0.stringValue.contains("Draft recovery could not be saved") })
    controller.close()
    // On-disk content is still the previous verified generation.
    let loaded = try await store.load()
    XCTAssertEqual(loaded.snapshot?.tabs[0].text, "")
  }

  private func allLabels(in view: NSView) -> [NSTextField] {
    (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { allLabels(in: $0) }
  }

  func testRestoresScrollSelectionAndClampsDisconnectedDisplayFrame() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "NoteHushAppTests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let text = (1...300).map { "Line \($0) with text" }.joined(separator: "\n")
    let anchor = (text as NSString).range(of: "Line 150 ").location
    let tab = TabSnapshot(
      text: text, selection: TextSelection(location: anchor, length: 8),
      scroll: TextScrollPosition(anchor: anchor, offset: 3))
    let seed = WorkspaceSnapshot(
      revision: 1, tabs: [tab], selectedTabID: tab.id,
      windowFrame: WindowFrame(x: 1_000_000, y: 1_000_000, width: 800, height: 500))
    let store = RecoveryStore(directory: directory)
    try await store.commit(seed)
    let controller = WorkspaceWindowController(directory: directory)
    controller.showWindow(nil)
    await controller.waitUntilLoaded()
    let editor = try XCTUnwrap(controller.tabs.first)
    XCTAssertEqual(editor.editor.selectedRange(), NSRange(location: anchor, length: 8))
    XCTAssertGreaterThan(editor.scrollView.contentView.bounds.minY, 1000)
    let frame = try XCTUnwrap(controller.window?.frame)
    XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.contains(frame) })
    let scrollBefore = editor.scrollView.contentView.bounds.minY
    controller.newTab(nil)
    controller.previousTab(nil)
    XCTAssertEqual(editor.scrollView.contentView.bounds.minY, scrollBefore, accuracy: 1)
    await controller.prepareToQuit()
    controller.close()
    let restored = WorkspaceWindowController(directory: directory)
    restored.showWindow(nil)
    await restored.waitUntilLoaded()
    XCTAssertEqual(restored.tabs.count, 2)
    XCTAssertEqual(restored.tabs[0].scrollView.contentView.bounds.minY, scrollBefore, accuracy: 1)
    XCTAssertEqual(restored.tabs[0].editor.selectedRange(), NSRange(location: anchor, length: 8))
    await restored.prepareToQuit()
    restored.close()
  }

  func testFutureSchemaDisablesEditingAndQuitLeavesOriginalBytesUntouched() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "NoteHushAppTests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let original = Data("{\"version\":900,\"newFormat\":\"preserve-me\"}".utf8)
    let primary = directory.appending(path: "session.json")
    try original.write(to: primary)
    let controller = WorkspaceWindowController(directory: directory)
    await controller.waitUntilLoaded()
    XCTAssertTrue(controller.tabs.isEmpty)
    controller.newTab(nil)
    XCTAssertTrue(controller.tabs.isEmpty)
    await controller.prepareToQuit()
    controller.close()
    XCTAssertEqual(try Data(contentsOf: primary), original)
    let export = try await RecoveryStore(directory: directory).exportGenerations()
    let decoded = try JSONDecoder().decode([String: Data].self, from: export)
    XCTAssertEqual(decoded["session.json"], original)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: directory.appending(path: "session.previous.json").path))
  }

  func testEditorUndoHistoryDoesNotCrossTabs() {
    _ = NSApplication.shared
    let first = EditorTab(snapshot: TabSnapshot(text: "first"))
    let second = EditorTab(snapshot: TabSnapshot(text: "second"))
    let firstHistory = first.undoManager(for: first.editor)
    let secondHistory = second.undoManager(for: second.editor)
    XCTAssertFalse(firstHistory === secondHistory)
    firstHistory?.beginUndoGrouping()
    first.editor.insertText("!", replacementRange: NSRange(location: 5, length: 0))
    firstHistory?.endUndoGrouping()
    secondHistory?.beginUndoGrouping()
    second.editor.insertText("?", replacementRange: NSRange(location: 6, length: 0))
    secondHistory?.endUndoGrouping()
    firstHistory?.undo()
    XCTAssertEqual(first.editor.string, "first")
    XCTAssertEqual(second.editor.string, "second?")
    secondHistory?.undo()
    XCTAssertEqual(second.editor.string, "second")
  }
}

private struct UnwritableRecoveryFiles: RecoveryFiles {
  func synchronizeDirectory() throws { throw RecoveryError.storageUnavailable }
  let base: DiskRecoveryFiles

  func read(_ name: String) throws -> Data? { try base.read(name) }
  func writeAtomically(_ data: Data, named name: String) throws {
    throw RecoveryError.storageUnavailable
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
