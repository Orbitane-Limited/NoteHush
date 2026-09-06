import AppKit
import NoteHushCore
import XCTest

@MainActor
final class SettingsControlTests: XCTestCase {
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
}
