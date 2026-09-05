import XCTest

@MainActor
final class WorkspaceLifecycleTests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchEnvironment["NOTEHUSH_TEST_WORKSPACE"] = UUID().uuidString
  }

  override func tearDown() async throws {
    app.terminate()
    app = nil
  }

  private var editor: XCUIElement { app.textViews["note-editor"].firstMatch }
  private var tabs: XCUIElementQuery {
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "tab-"))
  }

  private func launch() {
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
  }

  private func quit() {
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(
      app.wait(for: .notRunning, timeout: 10), "Quit must not wait for a save confirmation")
  }

  func testTabsIndependentUndoAndImmediateQuitRestoreSelection() {
    launch()
    editor.typeText("First draft")
    let firstID = tabs.element(boundBy: 0).identifier
    app.typeKey("n", modifierFlags: .command)
    editor.typeText("Second draft")
    let secondID = tabs.element(boundBy: 1).identifier
    app.typeKey("n", modifierFlags: .command)
    editor.typeText("Third draft")
    let preview = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    preview.name = "Three native tabs"
    preview.lifetime = .keepAlways
    add(preview)
    app.descendants(matching: .any)[secondID].click()
    XCTAssertEqual(editor.value as? String, "Second draft")
    editor.typeText(" changed")
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, "Second draft")
    app.descendants(matching: .any)[firstID].click()
    XCTAssertEqual(editor.value as? String, "First draft")
    app.descendants(matching: .any)[secondID].click()
    app.typeKey("a", modifierFlags: .command)
    quit()
    launch()
    XCTAssertEqual(tabs.count, 3)
    XCTAssertEqual(tabs.element(boundBy: 0).identifier, firstID)
    XCTAssertEqual(tabs.element(boundBy: 1).identifier, secondID)
    XCTAssertEqual(editor.value as? String, "Second draft")
    editor.typeText("Replaced selection")
    XCTAssertEqual(editor.value as? String, "Replaced selection")
    // No wait for an autosave: termination must capture this final change itself.
    quit()
    launch()
    XCTAssertEqual(editor.value as? String, "Replaced selection")
    app.descendants(matching: .any)[firstID].click()
    XCTAssertEqual(editor.value as? String, "First draft")
  }

  func testRedWindowCloseRestoresLatestDraftAndWindowFrame() {
    launch()
    let window = app.windows.firstMatch
    let originalFrame = window.frame
    editor.typeText("Close button draft")
    window.buttons[XCUIIdentifierCloseWindow].click()
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    launch()
    XCTAssertEqual(editor.value as? String, "Close button draft")
    XCTAssertEqual(app.windows.firstMatch.frame.width, originalFrame.width, accuracy: 2)
    XCTAssertEqual(app.windows.firstMatch.frame.height, originalFrame.height, accuracy: 2)
  }
}
