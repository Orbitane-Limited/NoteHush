#if NOTEHUSH_PERFORMANCE_TESTING
  import AppKit
  import os

  /// Passive event-dispatch intervals in the UUID-isolated optimized app only.
  /// No forced layout/display, document capture or event-timestamp subtraction.
  @MainActor
  final class PerformanceApplication: NSApplication {
    private let signposter = OSSignposter(
      subsystem: "pk.codehub.NoteHush.PerformanceTesting", category: "Interaction")
    private var completedEvents = 0

    override func sendEvent(_ event: NSEvent) {
      guard event.type == .keyDown, isActive, let window = keyWindow,
        event.window === window, window.isVisible, window.attachedSheet == nil,
        let editor = window.firstResponder as? NSTextView, editor.isEditable,
        editor.accessibilityIdentifier() == "note-editor"
      else {
        super.sendEvent(event)
        return
      }
      let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
      let name: StaticString
      if modifiers.isEmpty, event.charactersIgnoringModifiers == "x" {
        name = "TypingEventDispatch"
      } else if modifiers == [.control] || modifiers == [.control, .shift],
        event.charactersIgnoringModifiers == "\t" || event.charactersIgnoringModifiers == "\u{19}"
      {
        name = "TabEventDispatch"
      } else {
        super.sendEvent(event)
        return
      }
      let interval = signposter.beginInterval(name, id: signposter.makeSignpostID())
      super.sendEvent(event)
      signposter.endInterval(name, interval)
      // Publish only after the endpoint. The driver requires exactly one event
      // per measured action, rejecting missing or duplicate dispatch intervals.
      completedEvents += 1
      window.setAccessibilityIdentifier("performance-event-\(completedEvents)")
    }
  }
#endif
