import AppKit
import NoteHushCore
import XCTest

@MainActor
final class SettingsControlTests: XCTestCase {
  func testClosingSettingsCommitsActiveSizeEditBeforeAnotherPreferenceRefresh() throws {
    _ = NSApplication.shared
    for closeMethod in ["performClose", "closeButton", "controllerClose"] {
      var received = EditorPreferences()
      let controller = PreferencesWindowController(preferences: received) { received = $0 }
      let window = try XCTUnwrap(controller.window)
      defer { controller.close() }
      controller.showWindow(nil)
      window.makeKeyAndOrderFront(nil)
      let size = try sizeField(in: window)
      size.selectText(nil)
      let editor = try XCTUnwrap(size.currentEditor() as? NSTextView)
      editor.insertText(
        "22.5", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
      XCTAssertEqual(editor.string, "22.5")
      XCTAssertEqual(received.fontSize, 14, "Typing is still an uncommitted field edit")

      if closeMethod == "performClose" {
        window.performClose(nil)
      } else if closeMethod == "closeButton" {
        try XCTUnwrap(window.standardWindowButton(.closeButton)).performClick(nil)
      } else {
        controller.close()
      }
      XCTAssertFalse(window.isVisible, closeMethod)
      XCTAssertEqual(received.fontSize, 22.5, closeMethod)
      received.zoomPercent = 150
      controller.refresh(received)
      controller.showWindow(nil)
      XCTAssertEqual(size.doubleValue, 22.5, "Reopening after a zoom change: \(closeMethod)")
    }
  }

  func testClosingSettingsDiscardsInvalidSizeWithoutPreventingClose() throws {
    _ = NSApplication.shared
    for invalid in ["", "invalid", "2", "100"] {
      var received = EditorPreferences()
      let controller = PreferencesWindowController(preferences: received) { received = $0 }
      let window = try XCTUnwrap(controller.window)
      defer { controller.close() }
      controller.showWindow(nil)
      window.makeKeyAndOrderFront(nil)
      let size = try sizeField(in: window)
      size.selectText(nil)
      let editor = try XCTUnwrap(size.currentEditor() as? NSTextView)
      editor.insertText(
        invalid, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
      XCTAssertEqual(editor.string, invalid)
      window.performClose(nil)
      XCTAssertFalse(window.isVisible)
      XCTAssertEqual(received.fontSize, 14)
      controller.showWindow(nil)
      XCTAssertEqual(size.doubleValue, 14)
      XCTAssertNil(size.currentEditor())
    }
  }

  func testEndingSizeEditDoesNotResetPendingPopupSelectionBeforeItsAction() throws {
    _ = NSApplication.shared
    for (identifier, title) in [("appearance", "Dark"), ("zoom", "150%")] {
      var received = EditorPreferences()
      weak var receiver: PreferencesWindowController?
      let controller = PreferencesWindowController(preferences: received) { value in
        received = value
        // WorkspaceController sends the new preferences back to its Settings window.
        receiver?.refresh(value)
      }
      receiver = controller
      let views = descendants(try XCTUnwrap(controller.window?.contentView))
      let size = try XCTUnwrap(
        views.compactMap { $0 as? NSTextField }.first {
          $0.accessibilityIdentifier() == "font-size"
        })
      let popup = try XCTUnwrap(
        views.compactMap { $0 as? NSPopUpButton }.first {
          $0.accessibilityIdentifier() == identifier
        })
      size.doubleValue = 19
      popup.selectItem(withTitle: title)
      // Native control dispatch can finish the old field edit before delivering
      // the popup action. Committing the size must not reset that pending choice.
      controller.controlTextDidEndEditing(
        Notification(name: NSControl.textDidEndEditingNotification, object: size))
      XCTAssertEqual(popup.titleOfSelectedItem, title)
      XCTAssertTrue(popup.sendAction(popup.action, to: popup.target))
      XCTAssertEqual(received.fontSize, 19)
      if identifier == "appearance" {
        XCTAssertEqual(received.appearance, .dark)
      } else {
        XCTAssertEqual(received.zoomPercent, 150)
      }
      controller.close()
    }
  }

  private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  private func sizeField(in window: NSWindow) throws -> NSTextField {
    try XCTUnwrap(
      descendants(try XCTUnwrap(window.contentView)).compactMap { $0 as? NSTextField }
        .first { $0.accessibilityIdentifier() == "font-size" })
  }
}
