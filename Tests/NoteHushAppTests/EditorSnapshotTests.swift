import AppKit
import XCTest

@testable import NoteHushCore

@MainActor
final class EditorSnapshotTests: XCTestCase {
  func testMetadataAndAttributesReuseTextButDirectStorageEditsInvalidateCapture() throws {
    _ = NSApplication.shared
    let original = TabSnapshot(text: "\u{FEFF}ée\u{301}\r\n👩🏽‍💻")
    let tab = EditorTab(snapshot: original)
    let storage = try XCTUnwrap(tab.editor.textStorage)
    XCTAssertEqual(tab.snapshot(isVisible: false).textIdentity, original.textIdentity)
    tab.editor.setSelectedRange(NSRange(location: 2, length: 1))
    var preferences = EditorPreferences()
    preferences.fontSize = 20
    preferences.wordWrap = false
    tab.applyPreferences(preferences)
    storage.addAttribute(
      .foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: 1))
    let metadata = tab.snapshot(isVisible: false)
    XCTAssertEqual(metadata.textIdentity, original.textIdentity)
    XCTAssertEqual(metadata.selection, TextSelection(location: 2, length: 1))
    let replacement = "\u{FEFF}e\u{301}é\r\n👩🏽‍💻"
    XCTAssertEqual(replacement, original.text)
    storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: replacement)
    let edited = tab.snapshot(isVisible: false)
    XCTAssertNotEqual(edited.textIdentity, original.textIdentity)
    XCTAssertEqual(Array(edited.text.utf8), Array(replacement.utf8))
    XCTAssertEqual(Array(original.text.utf8), Array("\u{FEFF}ée\u{301}\r\n👩🏽‍💻".utf8))
    XCTAssertEqual(tab.snapshot(isVisible: false).textIdentity, edited.textIdentity)
    tab.editor.string = "programmatic replacement"
    let replaced = tab.snapshot(isVisible: false)
    XCTAssertEqual(replaced.text, "programmatic replacement")
    XCTAssertNotEqual(replaced.textIdentity, edited.textIdentity)
    storage.beginEditing()
    storage.replaceCharacters(
      in: NSRange(location: 0, length: storage.length), with: "batched change")
    let batched = tab.snapshot(isVisible: false)
    storage.endEditing()
    XCTAssertEqual(batched.text, "batched change")
  }

  func testMarkedTextCommitAndUndoAreCapturedExactly() throws {
    _ = NSApplication.shared
    let tab = EditorTab(snapshot: TabSnapshot(text: "start "))
    let original = tab.snapshot(isVisible: false)
    let history = try XCTUnwrap(tab.undoManager(for: tab.editor))
    // There is no run-loop event boundary in this synchronous fixture.
    history.groupsByEvent = false
    history.beginUndoGrouping()
    tab.editor.setMarkedText(
      "にほん", selectedRange: NSRange(location: 3, length: 0),
      replacementRange: NSRange(location: 6, length: 0))
    let marked = tab.snapshot(isVisible: false)
    XCTAssertEqual(marked.text, "start にほん")
    XCTAssertNotEqual(marked.textIdentity, original.textIdentity)
    tab.editor.insertText("日本", replacementRange: NSRange(location: NSNotFound, length: 0))
    history.endUndoGrouping()
    let committed = tab.snapshot(isVisible: false)
    XCTAssertEqual(committed.text, "start 日本")
    XCTAssertNotEqual(committed.textIdentity, marked.textIdentity)
    tab.editor.breakUndoCoalescing()
    history.beginUndoGrouping()
    tab.editor.insertText(
      "!", replacementRange: NSRange(location: tab.editor.textStorage?.length ?? 0, length: 0))
    history.endUndoGrouping()
    let edited = tab.snapshot(isVisible: false)
    XCTAssertEqual(edited.text, "start 日本!")
    history.undo()
    let undone = tab.snapshot(isVisible: false)
    XCTAssertEqual(Array(undone.text.utf8), Array(committed.text.utf8))
    XCTAssertNotEqual(undone.textIdentity, edited.textIdentity)
  }
}
