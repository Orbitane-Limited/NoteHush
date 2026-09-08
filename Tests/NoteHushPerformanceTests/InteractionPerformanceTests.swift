import AppKit
import CryptoKit
import XCTest

/// App dispatch and automation round trips are diagnostics, not display latency.
@MainActor
final class InteractionPerformanceTests: XCTestCase {
  private let bundleID = "pk.codehub.NoteHush.PerformanceTesting"
  private var owned: NSRunningApplication?

  override func setUp() async throws { continueAfterFailure = false }

  func testTypingASCII() throws { try run("typingASCII") }
  func testTypingMixed() throws { try run("typingMixed") }
  func testSwitchASCII() throws { try run("switchASCII") }
  func testSwitchMixed() throws { try run("switchMixed") }

  private struct Manifest: Decodable {
    let version: Int
    let applicationURL: URL
    let fixtures: [Fixture]
  }
  private struct Selection: Decodable {
    let location: Int
    let length: Int
  }
  private struct Fixture: Decodable {
    let name: String
    let workspace: UUID
    let selectedTab: UUID
    let targetTab: UUID
    let tabIDs: [UUID]
    let tabDigests: [Data]
    let tabSelections: [Selection]
  }

  private func run(_ name: String) throws {
    let manifestURL = URL(filePath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "build/interaction-fixtures.json")
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
    XCTAssertEqual(manifest.version, 1)
    XCTAssertEqual(
      manifest.fixtures.map(\.name), ["typingASCII", "typingMixed", "switchASCII", "switchMixed"])
    let fixture = try XCTUnwrap(manifest.fixtures.first { $0.name == name })
    XCTAssertEqual(fixture.tabIDs.count, fixture.tabDigests.count)
    XCTAssertEqual(fixture.tabIDs.count, fixture.tabSelections.count)
    let applicationURL = manifest.applicationURL.standardizedFileURL
    let bundle = try XCTUnwrap(Bundle(url: applicationURL))
    XCTAssertEqual(bundle.bundleIdentifier, bundleID)
    XCTAssertEqual(
      bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String, "NoteHushPerformance")
    XCTAssertEqual(
      bundle.object(forInfoDictionaryKey: "NoteHushRequiresTestWorkspace") as? String, "YES")
    XCTAssertEqual(
      bundle.object(forInfoDictionaryKey: "NoteHushPerformanceBuild") as? String, "YES")
    XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty)
    let app = XCUIApplication()
    app.launchEnvironment["NOTEHUSH_TEST_WORKSPACE"] = fixture.workspace.uuidString
    defer {
      // Only the exact bundle URL/identifier returned for this fixture is owned.
      if let owned, !owned.isTerminated {
        owned.forceTerminate()
        _ = app.wait(for: .notRunning, timeout: 20)
      }
    }
    try launch(app, applicationURL)
    let selected = try XCTUnwrap(fixture.tabIDs.firstIndex(of: fixture.selectedTab))
    let target = try XCTUnwrap(fixture.tabIDs.firstIndex(of: fixture.targetTab))
    requireSelected(app, fixture.tabIDs[selected])
    requireText(app, fixture.tabDigests[selected])
    if name.hasPrefix("typing") {
      XCTAssertEqual(selected, target)
      try measureTyping(app, fixture, selected)
    } else {
      try measureSwitching(app, fixture, selected, target)
    }
    // Visit every buffer outside collection, return to the original selection,
    // then restart normally and verify every buffer again. Host verification
    // also checks all saved selections, logical scroll lines/offsets and history.
    try verifyAllBuffers(app, fixture, selected)
    try quit(app)
    try launch(app, applicationURL)
    requireSelected(app, fixture.selectedTab)
    try verifyAllBuffers(app, fixture, selected)
    try quit(app)
  }

  private func measureTyping(_ app: XCUIApplication, _ fixture: Fixture, _ selected: Int) throws {
    let other = (selected + 1) % fixture.tabIDs.count
    // Keep a distinct edit in another tab through every measured edit/Undo.
    try switchTab(app, backwards: false)
    requireSelected(app, fixture.tabIDs[other])
    let otherText = try text(app)
    let otherEdited = replacing(otherText, fixture.tabSelections[other], "y")
    app.typeKey("y", modifierFlags: [])
    requireText(app, digest(otherEdited))
    try switchTab(app, backwards: true)
    requireSelected(app, fixture.selectedTab)
    let original = try text(app)
    XCTAssertEqual(digest(original), fixture.tabDigests[selected])
    let edited = digest(replacing(original, fixture.tabSelections[selected], "x"))
    let options = options()
    measure(metrics: metrics("TypingEventDispatch"), options: options) {
      do {
        try requireActive(app)
        requireSelected(app, fixture.selectedTab)
        requireText(app, fixture.tabDigests[selected])
        let before = try eventCount(app)
        startMeasuring()
        app.typeKey("x", modifierFlags: [])
        stopMeasuring()
        requireEvent(app, before + 1)
        requireText(app, edited)
        app.typeKey("z", modifierFlags: .command)
        requireText(app, fixture.tabDigests[selected])
      } catch { XCTFail("Typing fixture or dispatch identity failed") }
    }
    try switchTab(app, backwards: false)
    requireSelected(app, fixture.tabIDs[other])
    requireText(app, digest(otherEdited))
    app.typeKey("z", modifierFlags: .command)
    requireText(app, fixture.tabDigests[other])
    try switchTab(app, backwards: true)
    requireSelected(app, fixture.selectedTab)
  }

  private func measureSwitching(
    _ app: XCUIApplication, _ fixture: Fixture, _ selected: Int, _ target: Int
  ) throws {
    let backwards = target < selected
    let original = try text(app)
    let sourceEdited = digest(replacing(original, fixture.tabSelections[selected], "x"))
    let before = try eventCount(app)
    app.typeKey("x", modifierFlags: [])
    requireEvent(app, before + 1)
    requireText(app, sourceEdited)
    // Prime both selected viewports before collecting warmed switch samples.
    try switchTab(app, backwards: backwards)
    requireSelected(app, fixture.targetTab)
    let targetText = try text(app)
    XCTAssertEqual(digest(targetText), fixture.tabDigests[target])
    let targetEdited = digest(replacing(targetText, fixture.tabSelections[target], "y"))
    app.typeKey("y", modifierFlags: [])
    requireText(app, targetEdited)
    try switchTab(app, backwards: !backwards)
    requireSelected(app, fixture.selectedTab)
    requireText(app, sourceEdited)
    measure(metrics: metrics("TabEventDispatch"), options: options()) {
      do {
        try requireActive(app)
        requireSelected(app, fixture.selectedTab)
        requireText(app, sourceEdited)
        let before = try eventCount(app)
        startMeasuring()
        app.typeKey(.tab, modifierFlags: backwards ? [.control, .shift] : [.control])
        stopMeasuring()
        requireEvent(app, before + 1)
        requireSelected(app, fixture.targetTab)
        requireText(app, targetEdited)
        try switchTab(app, backwards: !backwards)
        requireSelected(app, fixture.selectedTab)
        requireText(app, sourceEdited)
      } catch { XCTFail("Tab fixture or dispatch identity failed") }
    }
    app.typeKey("z", modifierFlags: .command)
    requireText(app, fixture.tabDigests[selected])
    try switchTab(app, backwards: backwards)
    requireSelected(app, fixture.targetTab)
    requireText(app, targetEdited)
    app.typeKey("z", modifierFlags: .command)
    requireText(app, fixture.tabDigests[target])
    try switchTab(app, backwards: !backwards)
    requireSelected(app, fixture.selectedTab)
  }

  private func options() -> XCTMeasureOptions {
    let options = XCTMeasureOptions()
    options.iterationCount = 20
    options.invocationOptions = [.manuallyStart, .manuallyStop]
    return options
  }

  private func metrics(_ name: String) -> [any XCTMetric] {
    [
      XCTClockMetric(),
      XCTOSSignpostMetric(subsystem: bundleID, category: "Interaction", name: name),
    ]
  }

  private func launch(_ app: XCUIApplication, _ applicationURL: URL) throws {
    XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty)
    app.launch()
    let processes = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    XCTAssertEqual(processes.count, 1)
    let process = try XCTUnwrap(processes.first)
    guard process.bundleIdentifier == bundleID,
      process.bundleURL?.standardizedFileURL == applicationURL
    else {
      throw FixtureFailure.identity
    }
    owned = process
    XCTAssertTrue(app.windows["performance-editor-ready"].waitForExistence(timeout: 20))
    try requireActive(app)
  }

  private func requireActive(_ app: XCUIApplication) throws {
    let process = try XCTUnwrap(owned)
    XCTAssertFalse(process.isTerminated)
    XCTAssertTrue(process.isActive)
    XCTAssertEqual(app.state, .runningForeground)
    XCTAssertTrue(app.textViews["note-editor"].firstMatch.exists)
  }

  private func eventCount(_ app: XCUIApplication) throws -> Int {
    let identifier = app.windows.firstMatch.identifier
    if identifier == "performance-editor-ready" { return 0 }
    guard identifier.hasPrefix("performance-event-"),
      let count = Int(identifier.dropFirst("performance-event-".count)), count > 0
    else { throw FixtureFailure.identity }
    return count
  }

  private func requireEvent(_ app: XCUIApplication, _ count: Int) {
    XCTAssertTrue(
      app.windows["performance-event-\(count)"].waitForExistence(timeout: 5),
      "Require exactly one dispatch from the active native editor")
  }

  private func switchTab(_ app: XCUIApplication, backwards: Bool) throws {
    try requireActive(app)
    let before = try eventCount(app)
    app.typeKey(.tab, modifierFlags: backwards ? [.control, .shift] : [.control])
    requireEvent(app, before + 1)
  }

  private func verifyAllBuffers(_ app: XCUIApplication, _ fixture: Fixture, _ selected: Int) throws
  {
    for offset in 0..<fixture.tabIDs.count {
      let index = (selected + offset) % fixture.tabIDs.count
      requireSelected(app, fixture.tabIDs[index])
      requireText(app, fixture.tabDigests[index])
      try switchTab(app, backwards: false)
    }
    requireSelected(app, fixture.selectedTab)
  }

  private func requireSelected(_ app: XCUIApplication, _ id: UUID) {
    XCTAssertEqual(app.descendants(matching: .any)["tab-\(id.uuidString)"].value as? Int, 1)
  }

  private func text(_ app: XCUIApplication) throws -> String {
    try XCTUnwrap(app.textViews["note-editor"].firstMatch.value as? String)
  }

  private func requireText(_ app: XCUIApplication, _ expected: Data) {
    XCTAssertEqual((app.textViews["note-editor"].firstMatch.value as? String).map(digest), expected)
  }

  private func replacing(_ original: String, _ selection: Selection, _ insertion: String) -> String
  {
    (original as NSString).replacingCharacters(
      in: NSRange(location: selection.location, length: selection.length), with: insertion)
  }

  private func quit(_ app: XCUIApplication) throws {
    let process = try XCTUnwrap(owned)
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 20))
    XCTAssertTrue(process.isTerminated)
  }

  private enum FixtureFailure: Error { case identity }
  private func digest(_ text: String) -> Data { Data(SHA256.hash(data: Data(text.utf8))) }
}
