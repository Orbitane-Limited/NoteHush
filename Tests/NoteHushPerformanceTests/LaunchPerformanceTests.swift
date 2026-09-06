import AppKit
import CryptoKit
import NoteHushCore
import XCTest

/// Opt-in optimized measurements. The functional CI scheme does not run these.
@MainActor
final class LaunchPerformanceTests: XCTestCase {
  private let bundleID = "pk.codehub.NoteHush.PerformanceTesting"

  override func setUp() async throws { continueAfterFailure = false }

  func testEmptyWorkspaceLaunch() async throws {
    try await measureLaunch(open: 1, closed: 0, empty: true)
  }
  func testFiveMiBWorkspaceLaunch() async throws { try await measureLaunch(open: 20, closed: 0) }
  func testThirtyMiBWorkspaceLaunch() async throws {
    try await measureLaunch(open: 100, closed: 20)
  }

  private func measureLaunch(open: Int, closed: Int, empty: Bool = false) async throws {
    let path = try XCTUnwrap(ProcessInfo.processInfo.environment["NOTEHUSH_PERFORMANCE_APP"])
    let applicationURL = URL(filePath: path).standardizedFileURL
    let bundle = try XCTUnwrap(Bundle(url: applicationURL))
    XCTAssertEqual(bundle.bundleIdentifier, bundleID)
    XCTAssertEqual(
      bundle.object(forInfoDictionaryKey: "NoteHushRequiresTestWorkspace") as? String, "YES")
    XCTAssertEqual(
      bundle.object(forInfoDictionaryKey: "NoteHushPerformanceBuild") as? String, "YES")
    XCTAssertTrue(
      NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
      "Performance tests require exclusive ownership of the isolated app")
    let identifier = UUID()
    let recovery = FileManager.default.homeDirectoryForCurrentUser.appending(
      path:
        "Library/Containers/\(bundleID)/Data/Library/Application Support/NoteHush/UITests/\(identifier.uuidString)"
    )
    let app = XCUIApplication()
    app.launchEnvironment["NOTEHUSH_TEST_WORKSPACE"] = identifier.uuidString
    defer {
      if app.state != .notRunning { app.terminate() }
      if app.state == .notRunning { try? FileManager.default.removeItem(at: recovery) }
    }
    let editor = app.textViews["note-editor"].firstMatch
    // Untimed first launch lets macOS create/register the dedicated app container.
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 20))
    try requireProcess(applicationURL)
    try quit(app)
    let store = RecoveryStore(directory: recovery)
    let previous = try await store.load()
    let revision = try XCTUnwrap(previous.snapshot).revision
    XCTAssertLessThan(revision, UInt64.max)
    let expected = fixture(open: open, closed: closed, empty: empty, revision: revision + 1)
    try await store.commit(expected)
    let selected = try XCTUnwrap(expected.tabs.last)
    let selectedDigest = digest(selected.text)
    let options = XCTMeasureOptions()
    options.iterationCount = 20
    let readiness = XCTOSSignpostMetric(
      subsystem: bundleID, category: "Readiness", name: "ProcessToEditorReady")
    measure(
      metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true), readiness], options: options
    ) {
      app.launch()
      XCTAssertTrue(editor.waitForExistence(timeout: 20))
      // Both metric intervals have ended before these fixture assertions/teardown.
      // XCTest synchronization time is not represented as event-to-visible latency.
      do { try requireProcess(applicationURL) } catch {
        XCTFail("The expected performance process was not launched")
      }
      let selectedTab = app.descendants(matching: .any)["tab-\(selected.id.uuidString)"]
      XCTAssertTrue(selectedTab.isSelected)
      XCTAssertTrue(editor.isEnabled)
      let restored = editor.value as? String
      XCTAssertNotNil(restored)
      XCTAssertEqual(restored.map(digest), selectedDigest)
      do { try quit(app) } catch { XCTFail("The isolated app failed to terminate normally") }
    }
    // Check every tab/history buffer after the last measured normal termination.
    let final = try await store.load()
    let recovered = try XCTUnwrap(final.snapshot)
    XCTAssertEqual(recovered.tabs.map(\.id), expected.tabs.map(\.id))
    XCTAssertEqual(recovered.selectedTabID, expected.selectedTabID)
    XCTAssertEqual(recovered.tabs.map { digest($0.text) }, expected.tabs.map { digest($0.text) })
    XCTAssertEqual(
      recovered.closedTabs?.map { digest($0.tab.text) },
      expected.closedTabs?.map { digest($0.tab.text) })
  }

  @discardableResult
  private func requireProcess(_ applicationURL: URL) throws -> NSRunningApplication {
    let processes = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    XCTAssertEqual(processes.count, 1)
    let process = try XCTUnwrap(processes.first)
    XCTAssertEqual(process.bundleURL?.standardizedFileURL, applicationURL)
    return process
  }

  private func quit(_ app: XCUIApplication) throws {
    let process = try XCTUnwrap(
      NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first)
    XCTAssertTrue(process.terminate())
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 20))
  }

  private func fixture(open: Int, closed: Int, empty: Bool, revision: UInt64) -> WorkspaceSnapshot {
    let bytes = 256 * 1024
    let tails = ["generated line\r\n", "خط e\u{301} 📝.\r\n"].map {
      String(repeating: $0, count: bytes / 16 - 1)
    }
    func tab(_ index: Int) -> TabSnapshot {
      let text = empty ? "" : String(format: "tab-%010d\r\n", index) + tails[index % 2]
      precondition(empty || text.utf8.count == bytes)
      return TabSnapshot(text: text)
    }
    let tabs = (0..<open).map(tab)
    let history = (0..<closed).map { ClosedTabSnapshot(tab: tab(open + $0), originalIndex: $0) }
    // Fixtures always request at least one tab; index arithmetic is bounded here.
    return WorkspaceSnapshot(
      revision: revision, tabs: tabs, selectedTabID: tabs[open - 1].id, closedTabs: history)
  }

  private func digest(_ text: String) -> Data { Data(SHA256.hash(data: Data(text.utf8))) }
}
