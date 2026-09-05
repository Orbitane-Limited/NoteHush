import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var workspace: WorkspaceWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.mainMenu = makeMenu()
    let controller = WorkspaceWindowController()
    workspace = controller
    controller.showWindow(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

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
    return main
  }
}
