import XCTest

@MainActor
final class TabManagementUITests: XCTestCase {
  private var app: XCUIApplication!
  private var editor: XCUIElement { app.textViews["note-editor"].firstMatch }
  private var tabs: XCUIElementQuery {
    app.radioButtons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab-"))
  }

  override func setUp() async throws {
    continueAfterFailure = false
    executionTimeAllowance = 60
    app = XCUIApplication()
    app.launchEnvironment["NOTEHUSH_TEST_WORKSPACE"] = UUID().uuidString
  }

  override func tearDown() async throws { app.terminate() }

  private func launch() throws {
    app.launch()
    guard editor.waitForExistence(timeout: 10) else { throw Failure.missingEditor }
  }

  private func quit() throws {
    app.typeKey("q", modifierFlags: .command)
    guard app.wait(for: .notRunning, timeout: 10) else { throw Failure.didNotQuit }
  }

  func testPointerAndKeyboardReorderKeepSelectionAndRestoreOrder() throws {
    try launch()
    editor.typeText("First")
    let first = tabs.element(boundBy: 0).identifier
    app.typeKey("n", modifierFlags: .command)
    editor.typeText("Second")
    let second = tabs.element(boundBy: 1).identifier
    app.typeKey("n", modifierFlags: .command)
    editor.typeText("Third")
    let third = tabs.element(boundBy: 2).identifier
    let source = tabs.element(boundBy: 0).coordinate(
      withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    let target = tabs.element(boundBy: 2).coordinate(
      withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
    source.press(forDuration: 0.2, thenDragTo: target)
    XCTAssertEqual(tabs.allElementsBoundByIndex.map(\.identifier), [second, third, first])
    XCTAssertEqual(editor.value as? String, "Third")
    app.typeKey("[", modifierFlags: [.command, .control, .shift])
    XCTAssertEqual(tabs.allElementsBoundByIndex.map(\.identifier), [third, second, first])
    XCTAssertEqual(editor.value as? String, "Third")
    try quit()
    try launch()
    XCTAssertEqual(tabs.allElementsBoundByIndex.map(\.identifier), [third, second, first])
    XCTAssertEqual(editor.value as? String, "Third")
    let preview = XCTAttachment(screenshot: app.windows["NoteHush"].screenshot())
    preview.name = "Reordered tabs and close controls"
    preview.lifetime = .keepAlways
    add(preview)
  }

  func testCloseLastTabReopenAfterRestartAndClearHistory() throws {
    try launch()
    editor.typeText("Keep this closed draft")
    let original = tabs.element(boundBy: 0).identifier
    app.typeKey("a", modifierFlags: .command)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertEqual(app.state, .runningForeground)
    XCTAssertEqual(tabs.count, 1)
    XCTAssertEqual(editor.value as? String, "")
    try quit()
    try launch()
    app.typeKey("t", modifierFlags: [.command, .shift])
    XCTAssertEqual(tabs.count, 2)
    XCTAssertEqual(tabs.element(boundBy: 0).identifier, original)
    XCTAssertEqual(editor.value as? String, "Keep this closed draft")
    editor.typeText("Restored selection")
    XCTAssertEqual(editor.value as? String, "Restored selection")
    let id = String(original.dropFirst(4))
    app.buttons["close-tab-\(id)"].click()
    XCTAssertEqual(tabs.count, 1)
    app.menuBars.menuBarItems["File"].click()
    app.menuItems["Clear Recently Closed Tabs"].click()
    try quit()
    try launch()
    app.menuBars.menuBarItems["File"].click()
    XCTAssertFalse(app.menuItems["Reopen Closed Tab"].isEnabled)
    XCTAssertFalse(app.menuItems["Clear Recently Closed Tabs"].isEnabled)
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertEqual(tabs.count, 1)
    XCTAssertEqual(editor.value as? String, "")
  }

  func testOverflowMenuAndKeyboardNavigationRevealHiddenTabs() throws {
    try launch()
    editor.typeText("First overflow draft")
    let first = tabs.element(boundBy: 0).identifier
    for _ in 1...6 { app.typeKey("n", modifierFlags: .command) }
    editor.typeText("Last overflow draft")
    let last = tabs.element(boundBy: 6).identifier
    XCTAssertFalse(app.radioButtons[first].isHittable)
    app.typeKey("t", modifierFlags: [.command, .shift, .option])
    app.menuItems["1. Untitled •"].click()
    XCTAssertEqual(editor.value as? String, "First overflow draft")
    XCTAssertTrue(app.radioButtons[first].isHittable)
    app.typeKey(.tab, modifierFlags: [.control, .shift])
    XCTAssertEqual(editor.value as? String, "Last overflow draft")
    XCTAssertTrue(app.radioButtons[last].isHittable)
    app.buttons["all-tabs"].click()
    XCTAssertTrue(app.menuItems["7. Untitled 7 •"].exists)
    app.typeKey(.escape, modifierFlags: [])
  }

  private enum Failure: Error { case missingEditor, didNotQuit }
}
