import AppKit

@main
@MainActor
enum NoteHushMain {
  static func main() {
    #if NOTEHUSH_REQUIRE_TEST_WORKSPACE
      #if !DEBUG && !NOTEHUSH_PERFORMANCE_TESTING
        #error("An isolated configuration must route its workspace before it can launch")
      #endif
      // The dedicated UI-test app must never fall back to normal recovery.
      // Check before creating NSApplication or any workspace/window.
      guard let value = ProcessInfo.processInfo.environment["NOTEHUSH_TEST_WORKSPACE"],
        UUID(uuidString: value) != nil
      else { exit(EX_CONFIG) }
    #endif
    #if NOTEHUSH_PERFORMANCE_TESTING
      WorkspacePerformanceProbe.beginLaunch()
    #endif
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    // NSApplication keeps a weak reference to its delegate.
    withExtendedLifetime(delegate) {
      application.run()
    }
  }
}
