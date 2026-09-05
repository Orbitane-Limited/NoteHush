import Foundation
import XCTest

@testable import NoteHushCore

final class WorkspaceSnapshotTests: XCTestCase {
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
