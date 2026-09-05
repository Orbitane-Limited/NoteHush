import Foundation
import XCTest

@testable import NoteHushCore

final class WorkspaceSnapshotTests: XCTestCase {
  func testSchemaOneWithoutPresentationMetadataStillDecodes() throws {
    let id = UUID().uuidString
    let legacy = """
      {"revision":4,"selectedTabID":"\(id)","tabs":[{"id":"\(id)","title":"Draft","text":"hello","selection":{"location":2,"length":1}}]}
      """
    let workspace = try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(legacy.utf8))
    try workspace.validate()
    XCTAssertNil(workspace.windowFrame)
    XCTAssertNil(workspace.tabs[0].scroll)
    XCTAssertEqual(workspace.tabs[0].selection, TextSelection(location: 2, length: 1))
  }

  func testPresentationMetadataRoundTripsAndInvalidGeometryIsDetectable() throws {
    var workspace = WorkspaceSnapshot.empty()
    workspace.tabs[0].text = "First\nSecond"
    workspace.tabs[0].scroll = TextScrollPosition(anchor: 6, offset: 3.5)
    workspace.windowFrame = WindowFrame(x: -800, y: 42, width: 900, height: 600)
    let decoded = try JSONDecoder().decode(
      WorkspaceSnapshot.self, from: JSONEncoder().encode(workspace))
    XCTAssertEqual(decoded, workspace)
    XCTAssertTrue(decoded.windowFrame?.isValid == true)
    XCTAssertFalse(WindowFrame(x: .infinity, y: 0, width: 900, height: 600).isValid)
    XCTAssertFalse(WindowFrame(x: 0, y: 0, width: -1, height: 600).isValid)
  }

  func testFreshWorkspaceHasAnEditableSelectedTab() throws {
    let workspace = WorkspaceSnapshot.empty()
    try workspace.validate()
    XCTAssertEqual(workspace.tabs.count, 1)
    XCTAssertEqual(workspace.tabs[0].text, "")
    XCTAssertEqual(workspace.selectedTabID, workspace.tabs[0].id)
  }

  func testUnicodeSelectionUsesUTF16AndRoundTripsWithoutTextChanges() throws {
    let text = "Hello 👩🏽‍💻\r\nاردو e\u{301}\n"
    let tab = TabSnapshot(text: text, selection: TextSelection(location: text.utf16.count))
    let workspace = WorkspaceSnapshot(revision: 42, tabs: [tab], selectedTabID: tab.id)
    try workspace.validate()
    let decoded = try JSONDecoder().decode(
      WorkspaceSnapshot.self, from: JSONEncoder().encode(workspace))
    XCTAssertEqual(decoded, workspace)
    XCTAssertEqual(Array(decoded.tabs[0].text.utf8), Array(text.utf8))
  }

  func testInvalidWorkspaceIsRejected() {
    let tab = TabSnapshot()
    XCTAssertThrowsError(try WorkspaceSnapshot(tabs: [], selectedTabID: tab.id).validate())
    XCTAssertThrowsError(
      try WorkspaceSnapshot(tabs: [tab, tab], selectedTabID: tab.id).validate())
    XCTAssertThrowsError(
      try WorkspaceSnapshot(tabs: [tab], selectedTabID: UUID()).validate())
  }

  func testSelectionClampingCannotOverflow() {
    XCTAssertEqual(
      TextSelection(location: Int.max, length: Int.max).clamped(toUTF16Length: 4),
      TextSelection(location: 4))
    XCTAssertEqual(
      TextSelection(location: -1, length: Int.max).clamped(toUTF16Length: 4),
      TextSelection(location: 0, length: 4))
  }

  func testOutOfBoundsPersistedSelectionIsRejected() {
    let tab = TabSnapshot(text: "hi", selection: TextSelection(location: 3))
    XCTAssertThrowsError(
      try WorkspaceSnapshot(tabs: [tab], selectedTabID: tab.id).validate()
    ) { error in
      XCTAssertEqual(error as? WorkspaceValidationError, .invalidSelection(tab.id))
    }
  }
}
