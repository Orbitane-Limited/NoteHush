import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var workspace: WorkspaceWindowController?
  private var terminationTask: Task<Void, Never>?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.mainMenu = makeMenu()
    var directory = URL.applicationSupportDirectory.appending(
      path: "NoteHush/Recovery", directoryHint: .isDirectory)
    #if DEBUG
      // Only UUID-named, separate test workspaces are accepted; no arbitrary path or reset flag.
      if let value = ProcessInfo.processInfo.environment["NOTEHUSH_TEST_WORKSPACE"],
        let id = UUID(uuidString: value)
      {
        directory = URL.applicationSupportDirectory.appending(
          path: "NoteHush/UITests/\(id.uuidString)", directoryHint: .isDirectory)
      }
    #endif
    let controller = WorkspaceWindowController(directory: directory)
    workspace = controller
    controller.showWindow(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminationTask == nil {
      terminationTask = Task { [weak self] in
        await self?.workspace?.prepareToQuit()
        sender.reply(toApplicationShouldTerminate: true)
      }
    }
    return .terminateLater
  }

  @objc private func newTab(_ sender: Any?) { workspace?.newTab(sender) }
  @objc private func nextTab(_ sender: Any?) { workspace?.nextTab(sender) }
  @objc private func previousTab(_ sender: Any?) { workspace?.previousTab(sender) }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  private func makeMenu() -> NSMenu {
    let main = NSMenu()
    let appItem = NSMenuItem()
    main.addItem(appItem)
    let appMenu = NSMenu(title: "NoteHush")
    appMenu.addItem(
      withTitle: String(localized: "About NoteHush"),
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: String(localized: "Hide NoteHush"),
      action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: String(localized: "Quit NoteHush"),
      action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu

    let fileItem = NSMenuItem()
    main.addItem(fileItem)
    let file = NSMenu(title: String(localized: "File"))
    let new = file.addItem(
      withTitle: String(localized: "New Tab"), action: #selector(newTab(_:)), keyEquivalent: "n")
    new.target = self
    file.addItem(
      withTitle: String(localized: "Close Window"), action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w")
    fileItem.submenu = file

    let editItem = NSMenuItem()
    main.addItem(editItem)
    let edit = NSMenu(title: String(localized: "Edit"))
    edit.addItem(
      withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
    let redo = edit.addItem(
      withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(.separator())
    edit.addItem(
      withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(
      withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(
      withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"
    )
    edit.addItem(
      withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a")
    editItem.submenu = edit

    let windowItem = NSMenuItem()
    main.addItem(windowItem)
    let windowMenu = NSMenu(title: String(localized: "Window"))
    let next = windowMenu.addItem(
      withTitle: String(localized: "Next Tab"), action: #selector(nextTab(_:)), keyEquivalent: "\t")
    next.keyEquivalentModifierMask = [.control]
    next.target = self
    let previous = windowMenu.addItem(
      withTitle: String(localized: "Previous Tab"), action: #selector(previousTab(_:)),
      keyEquivalent: "\t")
    previous.keyEquivalentModifierMask = [.control, .shift]
    previous.target = self
    windowItem.submenu = windowMenu
    return main
  }
}
