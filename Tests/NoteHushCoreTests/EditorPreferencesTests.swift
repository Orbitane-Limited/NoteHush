import Foundation
import XCTest

@testable import NoteHushCore

@MainActor
final class EditorPreferencesTests: XCTestCase {
  func testUnsafePresentationValuesAreClampedWithoutAffectingDefaults() {
    var preferences = EditorPreferences()
    preferences.fontName = String(repeating: "x", count: 257)
    preferences.fontSize = .nan
    preferences.zoomPercent = Int.max
    XCTAssertNil(preferences.normalized.fontName)
    XCTAssertEqual(preferences.normalized.fontSize, 14)
    XCTAssertEqual(preferences.normalized.zoomPercent, 300)
    preferences.fontSize = -20
    preferences.zoomPercent = -100
    XCTAssertEqual(preferences.normalized.fontSize, 8)
    XCTAssertEqual(preferences.normalized.zoomPercent, 50)
    preferences.fontSize = 1_000
    XCTAssertEqual(preferences.normalized.fontSize, 72)
    XCTAssertTrue(EditorPreferences().wordWrap)
    XCTAssertFalse(EditorPreferences().checksSpelling)
  }

  func testZoomMovesToAdjacentStopsAndClampsAtEnds() {
    let preferences = EditorPreferences()
    XCTAssertEqual(preferences.zoomed(increasing: true).zoomPercent, 110)
    XCTAssertEqual(preferences.zoomed(increasing: false).zoomPercent, 90)
    var unusual = preferences
    unusual.zoomPercent = 117
    XCTAssertEqual(unusual.zoomed(increasing: true).zoomPercent, 125)
    XCTAssertEqual(unusual.zoomed(increasing: false).zoomPercent, 110)
    unusual.zoomPercent = 300
    XCTAssertEqual(unusual.zoomed(increasing: true).zoomPercent, 300)
    unusual.zoomPercent = 50
    XCTAssertEqual(unusual.zoomed(increasing: false).zoomPercent, 50)
  }

  func testSchemaThreeMigratesPreferencesKeepingExactPreviousGeneration() async throws {
    let fixture = try RecoveryFixture()
    let original = fixture.snapshot(revision: 1, text: "legacy\r\nاردو 👩🏽‍💻")
    let legacy = try legacyRecoveryEnvelope(original, version: 3)
    for name in [RecoveryStore.primaryName, RecoveryStore.previousName] {
      try legacy.write(to: fixture.directory.appending(path: name))
    }
    let loaded = try await fixture.store.load()
    XCTAssertEqual(loaded.snapshot, original)
    XCTAssertNil(loaded.snapshot?.preferences)
    var next = original
    next.revision = 2
    var preferences = EditorPreferences()
    preferences.fontName = "Menlo-Bold"
    preferences.fontSize = 18.5
    preferences.zoomPercent = 150
    preferences.appearance = .dark
    preferences.wordWrap = false
    preferences.checksSpelling = true
    next.preferences = preferences
    next.tabs[0].scroll = TextScrollPosition(anchor: 0, offset: 3, horizontalOffset: 150)
    try await fixture.store.commit(next)
    let restored = try await RecoveryStore(directory: fixture.directory).load()
    XCTAssertEqual(restored.snapshot, next)
    XCTAssertEqual(
      Array(try XCTUnwrap(restored.snapshot).tabs[0].text.utf8), Array(original.tabs[0].text.utf8))
    XCTAssertEqual(
      try Data(contentsOf: fixture.directory.appending(path: RecoveryStore.previousName)), legacy)
    let current = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.primary)) as? [String: Any])
    XCTAssertEqual(current["version"] as? Int, 6)
  }
}
