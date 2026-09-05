import AppKit
import XCTest

@MainActor
final class FilePanelTests: XCTestCase {
  private var app: XCUIApplication!
  private var root: URL!

  override func setUp() async throws {
    continueAfterFailure = false
    executionTimeAllowance = 60
    app = XCUIApplication()
    app.launchEnvironment["NOTEHUSH_TEST_WORKSPACE"] = UUID().uuidString
    root = FileManager.default.temporaryDirectory.appending(
      path: "NoteHushFilePanelTests-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    app.terminate()
    try FileManager.default.removeItem(at: root)
    app = nil
  }

  private var editor: XCUIElement { app.textViews["note-editor"].firstMatch }
  private func goTo(_ url: URL) {
    app.typeKey("g", modifierFlags: [.command, .shift])
    let field = app.textFields["PathTextField"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.click()
    app.typeKey("a", modifierFlags: .command)
    field.typeText(url.path)
    app.typeKey(.return, modifierFlags: [])
  }

  func testFinderStyleRequestOpensFileOnColdLaunch() async throws {
    let source = root.appending(path: "finder.txt")
    try Data("Finder launch fixture".utf8).write(to: source)
    let applicationURL = Bundle.main.bundleURL.deletingLastPathComponent().appending(
      path: "NoteHush.app")
    XCTAssertTrue(FileManager.default.fileExists(atPath: applicationURL.path))
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.environment = app.launchEnvironment
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      NSWorkspace.shared.open(
        [source], withApplicationAt: applicationURL, configuration: configuration
      ) { _, error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    let loaded = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "Finder launch fixture"), object: editor)
    await fulfillment(of: [loaded], timeout: 10)
  }

  func testNativeOpenAndSaveAsPreserveMixedNewlinesAndChosenExtension() throws {
    let source = root.appending(path: "source.conf")
    let destination = root.appending(path: "renamed.config")
    let text = "first\r\nsecond\nاردو 👩🏽‍💻\rtail"
    try Data(text.utf8).write(to: source)
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    app.typeKey("o", modifierFlags: .command)
    goTo(source)
    app.sheets.buttons["OKButton"].firstMatch.click()
    let loaded = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", text), object: editor)
    wait(for: [loaded], timeout: 10)
    app.menuBars.menuBarItems["File"].click()
    app.menuItems["Save As…"].click()
    let name = app.sheets.textFields["saveAsNameTextField"].firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    XCTAssertEqual(app.popUpButtons["save-encoding"].value as? String, "UTF-8")
    name.click()
    app.typeKey("a", modifierFlags: .command)
    name.typeText(destination.lastPathComponent)
    app.sheets.buttons["OKButton"].firstMatch.click()
    let saved = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        FileManager.default.fileExists(atPath: destination.path)
      }, object: nil)
    wait(for: [saved], timeout: 10)
    XCTAssertEqual(try Data(contentsOf: destination), Data(text.utf8))
    XCTAssertEqual(try Data(contentsOf: source), Data(text.utf8))
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    XCTAssertEqual(editor.value as? String, text)
  }

  func testCancelOpenAndSaveAsKeepUntitledDraft() {
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    editor.typeText("Keep this unsaved draft")
    app.typeKey("s", modifierFlags: .command)
    let cancel = app.sheets.buttons["CancelButton"].firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 5))
    cancel.click()
    XCTAssertEqual(editor.value as? String, "Keep this unsaved draft")
    app.typeKey("o", modifierFlags: .command)
    XCTAssertTrue(cancel.waitForExistence(timeout: 5))
    cancel.click()
    XCTAssertEqual(editor.value as? String, "Keep this unsaved draft")
  }

  func testQuitWithSaveAsPanelOpenRestoresDraftWithoutConfirmation() {
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    editor.typeText("Quit with save panel open")
    // The self-hosted Mac reserves Command-Shift-S for screen capture.
    app.menuBars.menuBarItems["File"].click()
    app.menuItems["Save As…"].click()
    XCTAssertTrue(app.sheets.textFields["saveAsNameTextField"].waitForExistence(timeout: 5))
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    XCTAssertEqual(editor.value as? String, "Quit with save panel open")
  }
}
