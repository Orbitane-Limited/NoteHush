import AppKit
import CryptoKit
import XCTest

/// Opt-in optimized measurements. The functional CI scheme does not run these.
@MainActor
final class LaunchPerformanceTests: XCTestCase {
  private let bundleID = "pk.codehub.NoteHush.PerformanceTesting"

  override func setUp() async throws { continueAfterFailure = false }

  func testEmptyWorkspaceLaunch() async throws {
    try measureLaunch("empty")
  }
  func testFiveMiBWorkspaceLaunch() async throws { try measureLaunch("fiveMiB") }
  func testThirtyMiBWorkspaceLaunch() async throws {
    try measureLaunch("thirtyMiB")
  }

  private struct Manifest: Decodable {
    let version: Int
    let applicationURL: URL
    let fixtures: [Fixture]
  }
  private struct Fixture: Decodable {
    let name: String
    let workspace: UUID
    let selectedTab: UUID
    let tabIDs: [UUID]
    let tabDigests: [Data]
  }

  private func measureLaunch(_ name: String) throws {
    // Xcode's UI runner is sandboxed. The host helper owns setup, complete buffer
    // verification and cleanup; this target reads only the generated manifest.
    let manifestURL = URL(filePath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "build/performance-fixtures.json")
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
    XCTAssertEqual(manifest.version, 1)
    let fixture = try XCTUnwrap(manifest.fixtures.first { $0.name == name })
    let selectedIndex = try XCTUnwrap(fixture.tabIDs.firstIndex(of: fixture.selectedTab))
    XCTAssertEqual(fixture.tabIDs.count, fixture.tabDigests.count)
    let selectedDigest = fixture.tabDigests[selectedIndex]
    let applicationURL = manifest.applicationURL.standardizedFileURL
    let bundle = try XCTUnwrap(Bundle(url: applicationURL))
    XCTAssertEqual(bundle.bundleIdentifier, bundleID)
    XCTAssertEqual(
      bundle.object(forInfoDictionaryKey: "NoteHushRequiresTestWorkspace") as? String, "YES")
    XCTAssertEqual(
      bundle.object(forInfoDictionaryKey: "NoteHushPerformanceBuild") as? String, "YES")
    XCTAssertTrue(
      NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
      "Performance tests require exclusive ownership of the isolated app")
    let app = XCUIApplication()
    app.launchEnvironment["NOTEHUSH_TEST_WORKSPACE"] = fixture.workspace.uuidString
    defer {
      if app.state != .notRunning { app.terminate() }
    }
    let editor = app.textViews["note-editor"].firstMatch
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
      let selectedTab = app.descendants(matching: .any)["tab-\(fixture.selectedTab.uuidString)"]
      XCTAssertEqual(selectedTab.value as? Int, 1)
      XCTAssertTrue(editor.isEnabled)
      let restored = editor.value as? String
      XCTAssertNotNil(restored)
      XCTAssertEqual(restored.map(digest), selectedDigest)
      do { try quit(app) } catch { XCTFail("The isolated app failed to terminate normally") }
    }
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

  private func digest(_ text: String) -> Data { Data(SHA256.hash(data: Data(text.utf8))) }
}
