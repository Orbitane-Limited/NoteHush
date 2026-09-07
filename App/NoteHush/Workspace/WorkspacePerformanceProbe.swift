#if NOTEHUSH_PERFORMANCE_TESTING
  import AppKit
  import os

  /// Compiled only into the isolated optimized performance app. Static interval
  /// names carry no document content, filesystem paths or bookmark metadata.
  @MainActor
  enum WorkspacePerformanceProbe {
    private static let signposter = OSSignposter(
      subsystem: "pk.codehub.NoteHush.PerformanceTesting", category: "Readiness")
    private static var launch: OSSignpostIntervalState?

    static func beginLaunch() {
      launch = signposter.beginInterval("ProcessToEditorReady", id: signposter.makeSignpostID())
    }

    static func editorReady(window: NSWindow?, editor: NSTextView?) {
      guard let launch, let window, let editor, window.isVisible, window.isKeyWindow,
        editor.isEditable, window.firstResponder === editor
      else { return }
      // AppKit layout/display may deliver nested window delegate callbacks.
      // Claim the interval first so those callbacks cannot complete it twice.
      self.launch = nil
      window.contentView?.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      // Nested AppKit callbacks can also change focus during layout/display.
      // Keep the interval pending until the actual endpoint has input focus.
      guard window.isVisible, window.isKeyWindow, editor.isEditable,
        window.firstResponder === editor
      else {
        self.launch = launch
        return
      }
      // This is an AppKit readiness boundary, not a display scan-out timestamp.
      signposter.endInterval("ProcessToEditorReady", launch)
      // The view can already be exposed to accessibility during native layout.
      // Publish completion after the endpoint so XCTest cannot stop too early.
      window.setAccessibilityIdentifier("performance-editor-ready")
    }
  }
#endif
