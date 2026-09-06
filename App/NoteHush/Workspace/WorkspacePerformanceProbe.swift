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
      guard let launch, let window, let editor, window.isVisible,
        editor.isEditable, window.firstResponder === editor
      else { return }
      window.contentView?.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      // This is an AppKit readiness boundary, not a display scan-out timestamp.
      signposter.endInterval("ProcessToEditorReady", launch)
      self.launch = nil
    }
  }
#endif
