import AppKit

@main
@MainActor
enum NoteHushMain {
  static func main() {
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
