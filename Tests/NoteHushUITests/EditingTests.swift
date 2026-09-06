import AppKit
import XCTest

@MainActor
final class EditingTests: XCTestCase {
  private var app: XCUIApplication!
  private var root: URL!
  private var savedFindItems: [[NSPasteboard.PasteboardType: Data]] = []

  override func setUp() async throws {
    continueAfterFailure = false
    executionTimeAllowance = 90
    app = XCUIApplication()
    app.launchEnvironment["NOTEHUSH_TEST_WORKSPACE"] = UUID().uuidString
    root = FileManager.default.temporaryDirectory.appending(path: "NoteHushEditingTests-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    // Native Find uses the shared Find pasteboard. Preserve it without logging
    // its contents; screenshots and queries below only contain test fixtures.
    let pasteboard = NSPasteboard(name: .find)
    savedFindItems = (pasteboard.pasteboardItems ?? []).map { item in
      Dictionary(
        uniqueKeysWithValues: item.types.compactMap { type in
          item.data(forType: type).map { (type, $0) }
        })
    }
    pasteboard.clearContents()
    pasteboard.setString("NoteHush fixture", forType: .string)
    pasteboard.setPropertyList(
      [
        NSPasteboard.PasteboardType.TextFinderOptionKey.textFinderCaseInsensitiveKey.rawValue:
          false,
        NSPasteboard.PasteboardType.TextFinderOptionKey.textFinderMatchingTypeKey.rawValue:
          NSTextFinder.MatchingType.contains.rawValue,
      ],
      forType: .textFinderOptions)
  }

  override func tearDown() async throws {
    app.terminate()
    let pasteboard = NSPasteboard(name: .find)
    let restored = savedFindItems.map { values in
      let item = NSPasteboardItem()
      for (type, data) in values { item.setData(data, forType: type) }
      return item
    }
    // Do not overwrite a new Find query entered in another app during a run.
    let fixtureQueries = ["", "NoteHush fixture", "café", "absent fixture", "needle"]
    if fixtureQueries.contains(pasteboard.string(forType: .string) ?? "") {
      pasteboard.clearContents()
      if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
    savedFindItems.removeAll()
    try FileManager.default.removeItem(at: root)
    app = nil
  }

  private var editor: XCUIElement { app.textViews["note-editor"].firstMatch }
  private func launch(text: String, assertsCompleteText: Bool = true) async throws {
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    let source = root.appending(path: "editing.txt")
    try Data(text.utf8).write(to: source)
    let applicationURL = Bundle.main.bundleURL.deletingLastPathComponent().appending(
      path: "NoteHush.app")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.allowsRunningApplicationSubstitution = false
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      NSWorkspace.shared.open(
        [source], withApplicationAt: applicationURL, configuration: configuration
      ) { _, error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    if assertsCompleteText {
      try await expect(editor, value: text)
    } else {
      let loaded = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value.length == %d", text.utf16.count), object: editor)
      let result = await XCTWaiter.fulfillment(of: [loaded], timeout: 15)
      guard result == .completed else { throw EditingTestFailure.expectedValueWasNotObserved }
    }
    XCTAssertEqual(
      app.radioButtons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab-")).count, 2)
  }

  private func expect(_ element: XCUIElement, value: String) async throws {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", value), object: element)
    let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 10)
    guard result == .completed else { throw EditingTestFailure.expectedValueWasNotObserved }
  }

  func testNativeFindReplaceUnicodeCaseAndIndependentUndo() async throws {
    let original = "café CAFÉ café\r\n👩🏽‍💻 second\nlast"
    try await launch(text: original)
    try await expect(app.staticTexts["status-counts"], value: "Characters: 28 · Selected: 0")
    try await expect(app.staticTexts["status-format"], value: "UTF-8 · Mixed")
    app.typeKey("f", modifierFlags: [.command, .option])
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.click()
    app.typeKey("a", modifierFlags: .command)
    search.typeText("café")
    app.typeKey(.return, modifierFlags: [])
    app.buttons["find next"].firstMatch.click()
    // AppKit previews matches while the find bar owns focus, then commits the
    // document selection when the user finishes searching.
    app.buttons["Done"].firstMatch.click()
    try await expect(app.staticTexts["status-counts"], value: "Characters: 28 · Selected: 4")
    app.typeKey("f", modifierFlags: [.command, .option])
    app.typeKey("g", modifierFlags: .command)
    let firstPosition = app.staticTexts["status-position"].value as? String
    app.typeKey("g", modifierFlags: .command)
    let secondPosition = app.staticTexts["status-position"].value as? String
    XCTAssertNotEqual(firstPosition, secondPosition)
    app.typeKey("g", modifierFlags: .command)
    try await expect(app.staticTexts["status-position"], value: try XCTUnwrap(firstPosition))
    app.typeKey("g", modifierFlags: [.command, .shift])
    try await expect(app.staticTexts["status-position"], value: try XCTUnwrap(secondPosition))
    try await expect(app.staticTexts["status-counts"], value: "Characters: 28 · Selected: 4")
    let replacement = app.textFields.matching(
      NSPredicate(format: "placeholderValue == %@", "Replace")
    ).firstMatch
    replacement.click()
    replacement.typeText("tea")
    app.buttons["Replace"].firstMatch.click()
    XCTAssertEqual((editor.value as? String)?.components(separatedBy: "tea").count, 2)
    // Undo goes to the document after focus returns from the replacement field.
    app.buttons["Done"].firstMatch.click()
    app.typeKey("z", modifierFlags: .command)
    try await expect(editor, value: original)
    app.typeKey("f", modifierFlags: [.command, .option])
    app.buttons["All"].firstMatch.click()
    try await expect(editor, value: "tea CAFÉ tea\r\n👩🏽‍💻 second\nlast")
    app.buttons["Done"].firstMatch.click()
    app.typeKey("z", modifierFlags: .command)
    try await expect(editor, value: original)
    app.typeKey("f", modifierFlags: [.command, .option])
    search.buttons["search"].click()
    app.menuItems["Ignore Case"].click()
    app.buttons["All"].firstMatch.click()
    try await expect(editor, value: "tea tea tea\r\n👩🏽‍💻 second\nlast")
    let preview = XCTAttachment(screenshot: app.windows["NoteHush"].screenshot())
    preview.name = "Native Find and editor status"
    preview.lifetime = .keepAlways
    add(preview)
    app.buttons["Done"].firstMatch.click()
    app.typeKey("n", modifierFlags: .command)
    editor.typeText("Separate draft")
    app.typeKey(.tab, modifierFlags: [.control, .shift])
    app.typeKey("z", modifierFlags: .command)
    try await expect(editor, value: original)
    app.typeKey(.tab, modifierFlags: .control)
    try await expect(editor, value: "Separate draft")
    XCTAssertEqual(try Data(contentsOf: root.appending(path: "editing.txt")), Data(original.utf8))
  }

  func testGoToLineStatusAndQuitWithSheetOpenPreserveDraft() async throws {
    let original = "👩🏽‍💻 first\r\nsecond\n"
    try await launch(text: original)
    try await expect(app.staticTexts["status-counts"], value: "Characters: 15 · Selected: 0")
    app.typeKey("a", modifierFlags: .command)
    try await expect(app.staticTexts["status-counts"], value: "Characters: 15 · Selected: 15")
    app.typeKey("l", modifierFlags: .command)
    let field = app.textFields["go-to-line-number"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    app.typeKey("a", modifierFlags: .command)
    field.typeText("0")
    XCTAssertFalse(app.sheets.buttons["Go"].isEnabled)
    app.typeKey("a", modifierFlags: .command)
    field.typeText("2")
    XCTAssertTrue(app.sheets.buttons["Go"].isEnabled)
    app.sheets.buttons["Go"].click()
    try await expect(app.staticTexts["status-position"], value: "Ln 2, Col 1")
    editor.typeText("X")
    try await expect(editor, value: "👩🏽‍💻 first\r\nXsecond\n")
    let window = app.windows["NoteHush"]
    let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
      .withOffset(CGVector(dx: -2, dy: -2))
    corner.press(forDuration: 0.1, thenDragTo: corner.withOffset(CGVector(dx: -480, dy: 0)))
    XCTAssertEqual(window.frame.width, 420, accuracy: 4)
    XCTAssertTrue(app.staticTexts["status-position"].isHittable)
    XCTAssertTrue(app.staticTexts["status-counts"].isHittable)
    XCTAssertTrue(app.staticTexts["status-format"].isHittable)
    app.typeKey("l", modifierFlags: .command)
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    let preview = XCTAttachment(screenshot: app.windows["NoteHush"].screenshot())
    preview.name = "Go to Line"
    preview.lifetime = .keepAlways
    add(preview)
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    try await expect(editor, value: "👩🏽‍💻 first\r\nXsecond\n")
    try await expect(app.staticTexts["status-position"], value: "Ln 2, Col 2")
    XCTAssertFalse(field.exists)
  }

  func testEmptyAndNoMatchSearchDoNotChangeText() async throws {
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    try await expect(app.staticTexts["status-counts"], value: "Characters: 0 · Selected: 0")
    try await expect(app.staticTexts["status-position"], value: "Ln 1, Col 1")
    try await expect(app.staticTexts["status-format"], value: "UTF-8 · No newlines")
    app.typeKey("f", modifierFlags: [.command, .option])
    let search = app.searchFields.firstMatch
    search.click()
    app.typeKey("a", modifierFlags: .command)
    app.typeKey(.delete, modifierFlags: [])
    app.typeKey("g", modifierFlags: .command)
    try await expect(editor, value: "")
    search.typeText("absent fixture")
    app.typeKey("g", modifierFlags: [.command, .shift])
    try await expect(editor, value: "")
    app.buttons["All"].firstMatch.click()
    try await expect(editor, value: "")
    app.buttons["Done"].firstMatch.click()
    app.typeKey("l", modifierFlags: .command)
    XCTAssertTrue(app.sheets.buttons["Go"].waitForExistence(timeout: 5))
    app.sheets.buttons["Go"].click()
    try await expect(app.staticTexts["status-position"], value: "Ln 1, Col 1")
  }

  func testFindInOneMiBDocumentKeepsTabsAndNavigationUsable() async throws {
    let text = String(repeating: "alpha beta text\n", count: 70_000) + "needle"
    try await launch(text: text, assertsCompleteText: false)
    try activateForKeyboardInput()
    app.typeKey("f", modifierFlags: .command)
    let search = app.searchFields.firstMatch
    guard search.waitForExistence(timeout: 5) else {
      attachTabTransitionFailure()
      throw EditingTestFailure.expectedValueWasNotObserved
    }
    search.click()
    app.typeKey("a", modifierFlags: .command)
    search.typeText("needle")
    XCTAssertEqual(search.value as? String, "needle")
    app.typeKey(.return, modifierFlags: [])
    app.buttons["Done"].firstMatch.click()
    app.typeKey("g", modifierFlags: .command)
    try await expect(app.staticTexts["status-position"], value: "Ln \(70_001.formatted()), Col 1")
    try await expect(
      app.staticTexts["status-counts"], value: "Characters: \(text.count.formatted()) · Selected: 6"
    )
    app.typeKey("n", modifierFlags: .command)
    editor.typeText("Still responsive")
    try await expect(editor, value: "Still responsive")
    try activateForKeyboardInput()
    app.typeKey(.tab, modifierFlags: [.control, .shift])
    do {
      try await expect(app.staticTexts["status-position"], value: "Ln \(70_001.formatted()), Col 1")
    } catch {
      attachTabTransitionFailure()
      throw error
    }
    app.typeKey("l", modifierFlags: .command)
    let field = app.textFields["go-to-line-number"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    app.typeKey("a", modifierFlags: .command)
    field.typeText("1")
    app.sheets.buttons["Go"].click()
    try await expect(app.staticTexts["status-position"], value: "Ln 1, Col 1")
  }

  private func activateForKeyboardInput() throws {
    app.activate()
    guard app.wait(for: .runningForeground, timeout: 5) else {
      throw EditingTestFailure.appDidNotBecomeForeground
    }
  }

  private func attachTabTransitionFailure() {
    // No desktop, shared Find pasteboard, or non-fixture text in diagnostics.
    let position = app.staticTexts["status-position"].value as? String ?? "missing"
    let length = (editor.value as? String)?.utf16.count ?? -1
    let detail = XCTAttachment(string: "Position: \(position); editor UTF-16 length: \(length)")
    detail.name = "Large Find keyboard transition"
    detail.lifetime = .keepAlways
    add(detail)
    let snapshot = XCTAttachment(screenshot: app.windows["NoteHush"].screenshot())
    snapshot.name = "Large Find keyboard transition"
    snapshot.lifetime = .keepAlways
    add(snapshot)
  }
}

private enum EditingTestFailure: Error {
  case expectedValueWasNotObserved, appDidNotBecomeForeground
}
