import XCTest

@MainActor
final class PreferencesUITests: XCTestCase {
  private var app: XCUIApplication!
  private var editor: XCUIElement { app.textViews["note-editor"].firstMatch }
  private var settings: XCUIElement { app.windows["Settings"] }

  override func setUp() async throws {
    continueAfterFailure = false
    executionTimeAllowance = 60
    app = XCUIApplication()
    app.launchEnvironment["NOTEHUSH_TEST_WORKSPACE"] = UUID().uuidString
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
  }

  override func tearDown() async throws { app.terminate() }

  private func openSettings() {
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
  }

  private func choose(_ identifier: String, _ title: String) {
    settings.popUpButtons[identifier].click()
    app.menuItems[title].click()
  }

  private func expect(_ element: XCUIElement, value: String) async throws {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", value), object: element)
    guard await XCTWaiter.fulfillment(of: [expectation], timeout: 8) == .completed else {
      throw PreferencesUIFailure.expectedValueWasNotObserved
    }
  }

  func testSettingsFontAppearanceWrapSpellingZoomAndQuitPersistence() async throws {
    let text = "literal \"quotes\" -- stay plain\nsecond line"
    editor.typeText(text)
    openSettings()
    choose("font-family", "Menlo")
    choose("font-face", "Bold")
    let size = settings.textFields["font-size"]
    size.click()
    app.typeKey("a", modifierFlags: .command)
    size.typeText("18")
    app.typeKey(.return, modifierFlags: [])
    choose("appearance", "Dark")
    choose("zoom", "150%")
    settings.checkBoxes["word-wrap"].click()
    settings.checkBoxes["check-spelling"].click()
    let preview = XCTAttachment(screenshot: settings.screenshot())
    preview.name = "Native editor settings"
    preview.lifetime = .keepAlways
    add(preview)
    // Commit a still-focused font size field through the actual Quit path.
    size.click()
    app.typeKey("a", modifierFlags: .command)
    size.typeText("19")
    app.typeKey("q", modifierFlags: .command)
    guard app.wait(for: .notRunning, timeout: 10) else { throw PreferencesUIFailure.didNotQuit }
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    try await expect(editor, value: text)
    openSettings()
    try await expect(settings.popUpButtons["font-family"], value: "Menlo")
    try await expect(settings.popUpButtons["font-face"], value: "Bold")
    try await expect(settings.textFields["font-size"], value: "19")
    try await expect(settings.popUpButtons["appearance"], value: "Dark")
    try await expect(settings.popUpButtons["zoom"], value: "150%")
    XCTAssertEqual(settings.checkBoxes["word-wrap"].value as? Int, 0)
    XCTAssertEqual(settings.checkBoxes["check-spelling"].value as? Int, 1)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertFalse(settings.exists)
    try await expect(editor, value: text)
  }

  func testZoomShortcutsAndAppearanceUpdatesKeepText() async throws {
    let text = "Zoom fixture"
    editor.typeText(text)
    app.typeKey("0", modifierFlags: .command)
    app.typeKey("=", modifierFlags: .command)
    openSettings()
    try await expect(settings.popUpButtons["zoom"], value: "110%")
    choose("appearance", "Light")
    app.typeKey("w", modifierFlags: .command)
    app.typeKey("-", modifierFlags: .command)
    openSettings()
    try await expect(settings.popUpButtons["zoom"], value: "100%")
    choose("appearance", "System")
    app.typeKey("w", modifierFlags: .command)
    try await expect(editor, value: text)
  }

  func testSettingsFontFamilyCanBeChangedWithKeyboard() async throws {
    openSettings()
    let family = settings.popUpButtons["font-family"]
    XCTAssertTrue(family.isHittable)
    // Cmd+, establishes initial focus; popup type-ahead selects the installed font.
    app.typeKey(.space, modifierFlags: [])
    app.typeText("Menlo")
    app.typeKey(.return, modifierFlags: [])
    try await expect(family, value: "Menlo")
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(editor.isHittable)
  }

  func testQuitWithNativePrintSheetRestoresDraftWithoutConfirmation() async throws {
    let text = "Print fixture draft\nUnsaved second line"
    editor.typeText(text)
    app.typeKey("p", modifierFlags: .command)
    XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 10))
    app.typeKey("q", modifierFlags: .command)
    guard app.wait(for: .notRunning, timeout: 10) else { throw PreferencesUIFailure.didNotQuit }
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    try await expect(editor, value: text)
    XCTAssertFalse(app.sheets.firstMatch.exists)
  }

  func testQuitWithNativePageSetupRestoresDraftWithoutConfirmation() async throws {
    let text = "Page setup fixture draft"
    editor.typeText(text)
    app.menuBarItems["File"].click()
    app.menuItems["Page Setup…"].click()
    XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 10))
    app.typeKey("q", modifierFlags: .command)
    guard app.wait(for: .notRunning, timeout: 10) else { throw PreferencesUIFailure.didNotQuit }
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    try await expect(editor, value: text)
    XCTAssertFalse(app.sheets.firstMatch.exists)
  }
}

private enum PreferencesUIFailure: Error { case expectedValueWasNotObserved, didNotQuit }
