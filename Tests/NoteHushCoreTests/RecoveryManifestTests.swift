import Foundation
import XCTest

@testable import NoteHushCore

final class RecoveryManifestTests: XCTestCase {
  func testManifestHydratesExactTextMetadataAndClosedHistory() throws {
    let binding = FileBinding(
      url: URL(filePath: "/generated-fixture/source.txt"),
      identity: FileIdentity(device: 1, inode: 2), encoding: .utf16BE,
      fileDigest: "original-file-digest", textDigest: "saved-text-digest",
      bookmark: Data([0, 1, 255]))
    let first = TabSnapshot(
      title: "First", text: "private draft\r\ne\u{301} 👩🏽‍💻", selection: TextSelection(location: 2),
      scroll: TextScrollPosition(anchor: 1, offset: 3, horizontalOffset: 7), file: binding)
    let second = TabSnapshot(title: "Second", text: "اردو\n", selection: TextSelection(location: 1))
    let closed = TabSnapshot(title: "Closed", text: "closed draft\r\n", file: binding)
    var preferences = EditorPreferences()
    preferences.fontSize = 19
    preferences.appearance = .dark
    preferences.wordWrap = false
    preferences.zoomPercent = 150
    let original = WorkspaceSnapshot(
      revision: 9, tabs: [first, second], selectedTabID: second.id,
      windowFrame: WindowFrame(x: 12, y: 34, width: 900, height: 600), preferences: preferences,
      closedTabs: [ClosedTabSnapshot(tab: closed, originalIndex: 1)])
    let manifest = try RecoveryManifest(snapshot: original) {
      try RecoveryBlobReference(text: $0.text)
    }
    try manifest.validate()
    let bytes = try JSONEncoder().encode(manifest)
    XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("private draft"))
    let decoded = try JSONDecoder().decode(RecoveryManifest.self, from: bytes)
    try decoded.validate()
    let texts = [first.id: first.text, second.id: second.text, closed.id: closed.text]
    let restored = try decoded.snapshot { id, reference in
      try reference.decode(Data(XCTUnwrap(texts[id]).utf8))
    }
    try restored.validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    XCTAssertEqual(try encoder.encode(restored), try encoder.encode(original))
    XCTAssertEqual(decoded.blobNames.count, 3)
    XCTAssertTrue(decoded.blobNames.allSatisfy { !$0.contains("/") && $0.hasSuffix(".utf8") })
  }

  func testBlobValidationRejectsByteChangesMalformedUTF8AndIncorrectLengths() throws {
    let first = "ée\u{301}"
    let second = "e\u{301}é"
    XCTAssertEqual(first, second)
    XCTAssertEqual(first.utf8.count, second.utf8.count)
    let reference = try RecoveryBlobReference(text: first)
    XCTAssertThrowsError(try reference.decode(Data(second.utf8)))
    let invalid = Data([0xFF])
    let malformed = try RecoveryBlobReference(
      sha256: RecoveryBlobReference.digest(invalid), utf8Count: 1, utf16Count: 1)
    XCTAssertThrowsError(try malformed.decode(invalid))
    let incorrectLength = try RecoveryBlobReference(
      sha256: reference.sha256, utf8Count: reference.utf8Count, utf16Count: 1)
    XCTAssertThrowsError(try incorrectLength.decode(Data(first.utf8)))
    XCTAssertThrowsError(try reference.decode(Data()))
  }

  func testLiteralBOMAndUnicodeBytesSurviveRawBlobDecoding() throws {
    for text in ["", "\u{FEFF}literal BOM", "\u{FEFF}\u{FEFF}two", "اردو\r\ne\u{301} 👩🏽‍💻"] {
      let reference = try RecoveryBlobReference(text: text)
      let restored = try reference.decode(Data(text.utf8))
      XCTAssertEqual(Array(restored.utf8), Array(text.utf8))
    }
  }

  func testUntrustedReferencesRejectTraversalAndInvalidBoundsDuringDecoding() throws {
    let valid = try RecoveryBlobReference(text: "abc")
    let encoded = try JSONEncoder().encode(valid)
    let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let invalid: [(String, Any)] = [
      ("sha256", "../../source"), ("sha256", String(repeating: "A", count: 64)),
      ("sha256", String(repeating: "a", count: 63)), ("utf8Count", -1),
      ("utf8Count", Int.max), ("utf16Count", -1), ("utf16Count", 4),
    ]
    for (key, value) in invalid {
      var changed = fields
      changed[key] = value
      XCTAssertThrowsError(
        try JSONDecoder().decode(
          RecoveryBlobReference.self, from: JSONSerialization.data(withJSONObject: changed)))
    }
  }

  func testDeclaredWorkspaceSizeIsBoundedBeforeHydration() throws {
    let first = TabSnapshot()
    let second = TabSnapshot()
    let snapshot = WorkspaceSnapshot(tabs: [first, second], selectedTabID: first.id)
    let reference = try RecoveryBlobReference(
      sha256: String(repeating: "a", count: 64),
      utf8Count: RecoveryBlobReference.maximumBytes, utf16Count: 1)
    let manifest = RecoveryManifest(snapshot: snapshot) { _ in reference }
    XCTAssertThrowsError(try manifest.validate()) {
      XCTAssertEqual($0 as? RecoveryError, .snapshotTooLarge)
    }
  }

  func testMetadataRejectsDuplicatesMissingSelectionAndMalformedHistory() throws {
    let first = TabSnapshot(text: "hi")
    let original = WorkspaceSnapshot(tabs: [first], selectedTabID: first.id)
    var duplicate = original
    duplicate.tabs.append(first)
    var missing = original
    missing.selectedTabID = UUID()
    var badSelection = original
    badSelection.tabs[0].selection = TextSelection(location: Int.max, length: Int.max)
    var badHistory = original
    badHistory.closedTabs = [ClosedTabSnapshot(tab: first, originalIndex: 0)]
    var negativeIndex = original
    negativeIndex.closedTabs = [ClosedTabSnapshot(tab: TabSnapshot(), originalIndex: -1)]
    var excessiveHistory = original
    excessiveHistory.closedTabs = (0...20).map {
      ClosedTabSnapshot(tab: TabSnapshot(), originalIndex: $0)
    }
    for snapshot in [duplicate, missing, badSelection, badHistory, negativeIndex, excessiveHistory]
    {
      let manifest = try RecoveryManifest(snapshot: snapshot) {
        try RecoveryBlobReference(text: $0.text)
      }
      XCTAssertThrowsError(try manifest.validate())
    }
  }
}
