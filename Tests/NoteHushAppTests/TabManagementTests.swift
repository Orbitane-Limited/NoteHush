import AppKit
import NoteHushCore
import XCTest

@MainActor
final class TabManagementTests: XCTestCase {
  func testReorderKeepsSelectedEditorUndoAndRestoresOrder() async throws {
    let fixture = try TabFixture(count: 3)
    let controller = try await fixture.load()
    let selected = try XCTUnwrap(controller.selectedTab)
    selected.editor.insertText("!", replacementRange: NSRange(location: 0, length: 0))
    selected.editor.setSelectedRange(NSRange(location: 2, length: 3))
    let responder = controller.window?.firstResponder
    controller.moveSelectedTab(by: 1)
    XCTAssertTrue(controller.selectedTab === selected)
    XCTAssertTrue(controller.window?.firstResponder === responder)
    XCTAssertEqual(selected.editor.selectedRange(), NSRange(location: 2, length: 3))
    XCTAssertTrue(selected.undoManager(for: selected.editor)?.canUndo == true)
    controller.moveTab(fixture.tabs[0].id, to: 1)
    let expected = [fixture.tabs[2].id, fixture.tabs[0].id, fixture.tabs[1].id]
    XCTAssertEqual(controller.tabs.map(\.id), expected)
    await controller.prepareToQuit()
    controller.close()
    let restored = try await fixture.load()
    XCTAssertEqual(restored.tabs.map(\.id), expected)
    XCTAssertEqual(restored.selectedTab?.id, selected.id)
    XCTAssertEqual(restored.selectedTab?.editor.selectedRange(), NSRange(location: 2, length: 3))
    await restored.prepareToQuit()
    restored.close()
  }

  func testCloseBackgroundAndLastTabRetainsTwentyNewest() async throws {
    let fixture = try TabFixture(count: 25)
    let controller = try await fixture.load()
    let selected = controller.selectedTab?.id
    controller.closeTab(fixture.tabs[0].id)
    XCTAssertEqual(controller.selectedTab?.id, selected)
    for tab in fixture.tabs.dropFirst() { controller.closeTab(tab.id) }
    XCTAssertEqual(controller.tabs.count, 1)
    XCTAssertEqual(controller.selectedTab?.editor.string, "")
    XCTAssertEqual(
      controller.closedTabs.map { $0.tab.id }, fixture.tabs.suffix(20).reversed().map(\.id))
    await controller.prepareToQuit()
    controller.close()
    let restored = try await fixture.load()
    XCTAssertEqual(restored.closedTabs.count, 20)
    restored.reopenClosedTab()
    XCTAssertEqual(restored.selectedTab?.id, fixture.tabs.last?.id)
    XCTAssertEqual(restored.closedTabs.count, 19)
    XCTAssertEqual(restored.tabs.count, 2)
    restored.clearClosedTabs()
    let open = restored.tabs.map(\.id)
    await restored.prepareToQuit()
    restored.close()
    let cleared = try await fixture.load()
    XCTAssertTrue(cleared.closedTabs.isEmpty)
    XCTAssertEqual(cleared.tabs.map(\.id), open)
    cleared.reopenClosedTab()
    XCTAssertEqual(cleared.tabs.map(\.id), open)
    await cleared.prepareToQuit()
    cleared.close()
  }

  func testReopenPreservesFileDraftSelectionScrollAndDetectsExternalEdit() async throws {
    let fixture = try TabFixture(count: 1)
    let file = fixture.directory.appending(path: "named.txt")
    let original = (1...300).map { "Line \($0) اردو 👩🏽‍💻" }.joined(separator: "\r\n")
    try TextDocumentCodec.encode(original, as: .utf16BE).write(to: file)
    let controller = try await fixture.load()
    _ = await controller.openFiles([file])
    let tab = try XCTUnwrap(controller.selectedTab)
    tab.editor.insertText("draft ", replacementRange: NSRange(location: 0, length: 0))
    let text = tab.editor.string
    let selection = (text as NSString).range(of: "Line 150")
    tab.editor.setSelectedRange(selection)
    XCTAssertEqual(tab.editor.selectedRange(), selection)
    tab.editor.scrollRangeToVisible(selection)
    let scroll = tab.scrollView.contentView.bounds.minY
    let binding = tab.file
    controller.closeSelectedTab()
    await controller.prepareToQuit()
    controller.close()
    try Data("external change".utf8).write(to: file, options: .atomic)
    let restored = try await fixture.load()
    restored.reopenClosedTab()
    let reopened = try XCTUnwrap(restored.selectedTab)
    XCTAssertEqual(reopened.id, tab.id)
    XCTAssertEqual(Data(reopened.editor.string.utf8), Data(text.utf8))
    XCTAssertEqual(reopened.file, binding)
    XCTAssertEqual(reopened.editor.selectedRange(), selection)
    XCTAssertEqual(reopened.scrollView.contentView.bounds.minY, scroll, accuracy: 1)
    let saved = await restored.saveFile(reopened, to: file, encoding: .utf16BE, saveAs: false)
    XCTAssertFalse(saved)
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "external change")
    await restored.prepareToQuit()
    restored.close()
  }

  func testReopeningDuplicateFileKeepsBothTextsWithoutDuplicateBinding() async throws {
    let fixture = try TabFixture(count: 1)
    let file = fixture.directory.appending(path: "same.txt")
    try Data("original".utf8).write(to: file)
    let controller = try await fixture.load()
    _ = await controller.openFiles([file])
    let first = try XCTUnwrap(controller.selectedTab)
    first.editor.insertText("draft ", replacementRange: NSRange(location: 0, length: 0))
    controller.closeSelectedTab()
    _ = await controller.openFiles([file])
    let second = try XCTUnwrap(controller.selectedTab)
    controller.reopenClosedTab()
    XCTAssertEqual(controller.selectedTab?.editor.string, "draft original")
    XCTAssertNil(controller.selectedTab?.file)
    XCTAssertEqual(second.editor.string, "original")
    XCTAssertNotNil(second.file)
    XCTAssertEqual(controller.tabs.filter { $0.file != nil }.count, 1)
    await controller.prepareToQuit()
    controller.close()
  }

  func testHundredTabsExposeNamesCloseControlsStableButtonsAndOverflow() async throws {
    let fixture = try TabFixture(count: 100)
    let controller = try await fixture.load()
    controller.window?.setContentSize(NSSize(width: 420, height: 300))
    let buttons = descendants(try XCTUnwrap(controller.window?.contentView)).compactMap {
      $0 as? NSButton
    }
    let tabButtons = buttons.filter { $0.accessibilityIdentifier().hasPrefix("tab-") == true }
    XCTAssertEqual(tabButtons.count, 100)
    XCTAssertEqual(
      buttons.filter { $0.accessibilityIdentifier().hasPrefix("close-tab-") == true }.count, 100)
    let newTabButton = try XCTUnwrap(
      buttons.first { $0.accessibilityIdentifier() == "new-tab" })
    XCTAssertEqual(newTabButton.accessibilityLabel(), "New Tab")
    let allTabsButton = try XCTUnwrap(
      buttons.first { $0.accessibilityIdentifier() == "all-tabs" })
    XCTAssertEqual(allTabsButton.accessibilityLabel(), "All Tabs")
    XCTAssertTrue(tabButtons.allSatisfy { $0.accessibilityRole() == .radioButton })
    XCTAssertTrue(
      tabButtons.allSatisfy { $0.accessibilityLabel()?.contains("unsaved changes") == true })
    XCTAssertEqual(tabButtons.filter { $0.state == .on }.count, 1)
    controller.previousTab(nil)
    controller.previousTab(nil)  // Wrap from first to last and reveal it.
    let last = try XCTUnwrap(tabButtons.last)
    XCTAssertEqual(controller.selectedTab?.id, fixture.tabs.last?.id)
    XCTAssertEqual(last.accessibilityLabel(), "Draft 100, tab 100 of 100")
    XCTAssertEqual(last.state, .on)
    let lastCloseButton = try XCTUnwrap(
      buttons.first {
        $0.accessibilityIdentifier() == "close-tab-\(fixture.tabs[99].id.uuidString)"
      })
    XCTAssertEqual(lastCloseButton.accessibilityLabel(), "Close Draft 100")
    XCTAssertFalse(last.visibleRect.isEmpty)
    last.performClick(nil)
    XCTAssertEqual(last.state, .on, "Clicking the active tab must not deselect it")
    controller.selectedTab?.editor.insertText(
      "x", replacementRange: NSRange(location: 0, length: 0))
    let current = descendants(controller.tabBar).compactMap { $0 as? NSButton }
    XCTAssertTrue(current.contains { $0 === last })
    XCTAssertTrue(last.accessibilityLabel()?.contains("unsaved changes") == true)
    let menu = controller.tabBar.allTabsMenu()
    XCTAssertEqual(menu.items.count, 100)
    XCTAssertEqual(menu.items.last?.state, .on)
    XCTAssertEqual(menu.items.last?.representedObject as? UUID, fixture.tabs.last?.id)
    XCTAssertFalse(controller.canMoveSelectedTab(by: 1))
    XCTAssertTrue(controller.canMoveSelectedTab(by: -1))
    await controller.prepareToQuit()
    controller.close()
  }

  func testCloseIsUnavailableDuringAcceptedSave() async throws {
    let fixture = try TabFixture(count: 1)
    let file = fixture.directory.appending(path: "saving.txt")
    try Data("saved".utf8).write(to: file)
    let service = GatedFileAccess()
    let controller = WorkspaceWindowController(
      store: RecoveryStore(directory: fixture.directory.appending(path: "Recovery")),
      fileService: service)
    _ = await controller.openFiles([file])
    let selected = try XCTUnwrap(controller.selectedTab)
    controller.saveDocument(nil)
    await service.waitForSave()
    selected.editor.insertText(" later", replacementRange: NSRange(location: 5, length: 0))
    controller.closeSelectedTab()
    XCTAssertEqual(controller.selectedTab?.id, selected.id)
    XCTAssertTrue(controller.closedTabs.isEmpty)
    await service.releaseSave()
    await controller.savingTask?.value
    controller.closeSelectedTab()
    XCTAssertEqual(controller.closedTabs.first?.tab.id, selected.id)
    XCTAssertEqual(controller.closedTabs.first?.tab.text, "saved later")
    XCTAssertEqual(
      controller.closedTabs.first?.tab.file?.textDigest, TextDocumentCodec.textDigest("saved"))
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "saved")
    await controller.prepareToQuit()
    controller.close()
  }

  private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }
}

@MainActor
private final class TabFixture {
  let directory: URL
  let tabs: [TabSnapshot]
  init(count: Int) throws {
    _ = NSApplication.shared
    directory = FileManager.default.temporaryDirectory.appending(path: "NoteHushTabs-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    tabs = (1...count).map { TabSnapshot(title: "Draft \($0)", text: "Text \($0) اردو 👩🏽‍💻") }
  }
  func load() async throws -> WorkspaceWindowController {
    let store = RecoveryStore(directory: directory.appending(path: "Recovery"))
    if try await store.load().snapshot == nil {
      try await store.commit(
        WorkspaceSnapshot(revision: 1, tabs: tabs, selectedTabID: tabs[min(1, tabs.count - 1)].id))
    }
    let controller = WorkspaceWindowController(store: store)
    controller.showWindow(nil)
    await controller.waitUntilLoaded()
    return controller
  }
  deinit { try? FileManager.default.removeItem(at: directory) }
}
