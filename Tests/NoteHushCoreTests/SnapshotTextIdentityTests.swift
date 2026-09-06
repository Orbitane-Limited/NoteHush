import Foundation
import XCTest

@testable import NoteHushCore

final class SnapshotTextIdentityTests: XCTestCase {
  func testMetadataCopiesShareIdentityWhileTextAssignmentsInvalidateIt() {
    let original = TabSnapshot(text: "é\r\n👩🏽‍💻")
    var copy = original
    copy.selection = TextSelection(location: 1)
    copy.title = "changed title"
    XCTAssertEqual(copy.textIdentity, original.textIdentity)
    copy.text = "e\u{301}\r\n👩🏽‍💻"
    XCTAssertEqual(copy.text, original.text, "Canonical equality cannot identify stored bytes")
    XCTAssertNotEqual(copy.textIdentity, original.textIdentity)
    XCTAssertNotEqual(Array(copy.text.utf8), Array(original.text.utf8))
    let assigned = copy.textIdentity
    copy.text += "x"
    XCTAssertNotEqual(copy.textIdentity, assigned)
    XCTAssertEqual(Array(original.text.utf8), Array("é\r\n👩🏽‍💻".utf8))
  }

  func testIdentityCannotBeSerializedOrInjectedIntoLegacyPayload() throws {
    let original = TabSnapshot(text: "اردو e\u{301}", selection: TextSelection(location: 1))
    let encoded = try JSONEncoder().encode(original)
    var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    XCTAssertEqual(Set(fields.keys), Set(["id", "title", "text", "selection"]))
    XCTAssertEqual(fields["text"] as? String, original.text)
    fields["textIdentity"] = original.textIdentity.uuidString
    let decoded = try JSONDecoder().decode(
      TabSnapshot.self, from: JSONSerialization.data(withJSONObject: fields))
    XCTAssertEqual(decoded, original)
    XCTAssertNotEqual(decoded.textIdentity, original.textIdentity)
    XCTAssertEqual(Array(decoded.text.utf8), Array(original.text.utf8))
  }
}
