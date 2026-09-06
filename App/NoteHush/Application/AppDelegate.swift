import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
  private var workspace: WorkspaceWindowController?
  private var terminationTask: Task<Void, Never>?
  private var pendingOpenURLs: [URL] = []

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
    if !pendingOpenURLs.isEmpty {
      controller.beginOpening(pendingOpenURLs)
      pendingOpenURLs.removeAll()
    }
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    if let workspace {
      workspace.beginOpening(urls)
    } else {
      pendingOpenURLs.append(contentsOf: urls)
    }
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
  @objc private func openDocument(_ sender: Any?) { workspace?.openDocument(sender) }
  @objc private func saveDocument(_ sender: Any?) { workspace?.saveDocument(sender) }
  @objc private func saveDocumentAs(_ sender: Any?) { workspace?.saveDocumentAs(sender) }
  @objc private func performTextFinderAction(_ sender: Any?) {
    workspace?.performFindAction(sender)
  }
  @objc private func goToLine(_ sender: Any?) { workspace?.goToLine(sender) }
  @objc private func showSettings(_ sender: Any?) { workspace?.showPreferences() }
  @objc private func zoomIn(_ sender: Any?) { workspace?.zoom(increasing: true) }
  @objc private func zoomOut(_ sender: Any?) { workspace?.zoom(increasing: false) }
  @objc private func resetZoom(_ sender: Any?) { workspace?.resetZoom() }
  @objc private func toggleWordWrap(_ sender: Any?) { workspace?.toggleWordWrap() }
  @objc private func pageSetup(_ sender: Any?) { workspace?.showPageSetup() }
  @objc private func printDocument(_ sender: Any?) {
    workspace?.printDocument(selectionOnly: false)
  }
  @objc private func printSelection(_ sender: Any?) {
    workspace?.printDocument(selectionOnly: true)
  }
  @objc private func closeTab(_ sender: Any?) {
    if let key = NSApp.keyWindow, key !== workspace?.window {
      key.performClose(sender)
    } else {
      workspace?.closeSelectedTab()
    }
  }
  @objc private func reopenClosedTab(_ sender: Any?) { workspace?.reopenClosedTab() }
  @objc private func clearClosedTabs(_ sender: Any?) { workspace?.clearClosedTabs() }
  @objc private func moveTabLeft(_ sender: Any?) { workspace?.moveSelectedTab(by: -1) }
  @objc private func moveTabRight(_ sender: Any?) { workspace?.moveSelectedTab(by: 1) }
  @objc private func showAllTabs(_ sender: Any?) { workspace?.tabBar.showAllTabs(sender) }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(closeTab(_:)):
      let auxiliary = NSApp.keyWindow != nil && NSApp.keyWindow !== workspace?.window
      menuItem.title =
        auxiliary ? String(localized: "Close Window") : String(localized: "Close Tab")
      return auxiliary
        ? NSApp.keyWindow?.styleMask.contains(.closable) == true
        : workspace?.canManageTabs == true
    case #selector(reopenClosedTab(_:)), #selector(clearClosedTabs(_:)):
      return workspace?.canManageTabs == true && workspace?.closedTabs.isEmpty == false
    case #selector(moveTabLeft(_:)): return workspace?.canMoveSelectedTab(by: -1) == true
    case #selector(moveTabRight(_:)): return workspace?.canMoveSelectedTab(by: 1) == true
    case #selector(showAllTabs(_:)): return workspace?.canNavigate == true
    case #selector(zoomIn(_:)):
      return workspace?.canNavigate == true && (workspace?.preferences.zoomPercent ?? 300) < 300
    case #selector(zoomOut(_:)):
      return workspace?.canNavigate == true && (workspace?.preferences.zoomPercent ?? 50) > 50
    case #selector(toggleWordWrap(_:)):
      menuItem.state = workspace?.preferences.wordWrap == true ? .on : .off
      return workspace?.canNavigate ?? false
    case #selector(printSelection(_:)):
      return workspace?.canNavigate == true
        && (workspace?.selectedTab?.editor.selectedRange().length ?? 0) > 0
    case #selector(performTextFinderAction(_:)):
      return workspace?.validateFindAction(menuItem) ?? false
    case #selector(goToLine(_:)), #selector(newTab(_:)), #selector(nextTab(_:)),
      #selector(previousTab(_:)), #selector(openDocument(_:)), #selector(saveDocument(_:)),
      #selector(saveDocumentAs(_:)), #selector(showSettings(_:)), #selector(resetZoom(_:)),
      #selector(pageSetup(_:)), #selector(printDocument(_:)):
      return workspace?.canNavigate ?? false
    default: return true
    }
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
    let settings = appMenu.addItem(
      withTitle: String(localized: "Settings…"), action: #selector(showSettings(_:)),
      keyEquivalent: ",")
    settings.target = self
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
    let open = file.addItem(
      withTitle: String(localized: "Open…"), action: #selector(openDocument(_:)), keyEquivalent: "o"
    )
    open.target = self
    let save = file.addItem(
      withTitle: String(localized: "Save"), action: #selector(saveDocument(_:)), keyEquivalent: "s")
    save.target = self
    let saveAs = file.addItem(
      withTitle: String(localized: "Save As…"), action: #selector(saveDocumentAs(_:)),
      keyEquivalent: "s")
    saveAs.keyEquivalentModifierMask = [.command, .shift]
    saveAs.target = self
    file.addItem(.separator())
    for (title, action, key) in [
      (String(localized: "Page Setup…"), #selector(pageSetup(_:)), ""),
      (String(localized: "Print…"), #selector(printDocument(_:)), "p"),
      (String(localized: "Print Selection…"), #selector(printSelection(_:)), ""),
    ] {
      file.addItem(withTitle: title, action: action, keyEquivalent: key).target = self
    }
    file.addItem(.separator())
    file.addItem(
      withTitle: String(localized: "Close Tab"), action: #selector(closeTab(_:)),
      keyEquivalent: "w"
    ).target = self
    let closeWindow = file.addItem(
      withTitle: String(localized: "Close Window"), action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w")
    closeWindow.keyEquivalentModifierMask = [.command, .shift]
    let reopen = file.addItem(
      withTitle: String(localized: "Reopen Closed Tab"), action: #selector(reopenClosedTab(_:)),
      keyEquivalent: "t")
    reopen.target = self
    reopen.keyEquivalentModifierMask = [.command, .shift]
    let clear = file.addItem(
      withTitle: String(localized: "Clear Recently Closed Tabs"),
      action: #selector(clearClosedTabs(_:)),
      keyEquivalent: "")
    clear.target = self
    clear.toolTip = String(
      localized:
        "Remove the 20 most recent closed drafts. Open drafts and damaged recovery evidence are kept."
    )
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
    edit.addItem(.separator())
    let findItem = NSMenuItem(title: String(localized: "Find"), action: nil, keyEquivalent: "")
    let find = NSMenu(title: String(localized: "Find"))
    for (title, action, key, modifiers) in [
      (
        String(localized: "Find…"), NSTextFinder.Action.showFindInterface, "f",
        NSEvent.ModifierFlags.command
      ),
      (String(localized: "Find and Replace…"), .showReplaceInterface, "f", [.command, .option]),
      (String(localized: "Find Next"), .nextMatch, "g", .command),
      (String(localized: "Find Previous"), .previousMatch, "g", [.command, .shift]),
      (String(localized: "Use Selection for Find"), .setSearchString, "e", .command),
    ] {
      let item = find.addItem(
        withTitle: title, action: #selector(performTextFinderAction(_:)),
        keyEquivalent: key)
      item.target = self
      item.tag = action.rawValue
      item.keyEquivalentModifierMask = modifiers
    }
    findItem.submenu = find
    edit.addItem(findItem)
    let goTo = edit.addItem(
      withTitle: String(localized: "Go to Line…"),
      action: #selector(goToLine(_:)), keyEquivalent: "l")
    goTo.target = self
    editItem.submenu = edit

    let viewItem = NSMenuItem()
    main.addItem(viewItem)
    let view = NSMenu(title: String(localized: "View"))
    for (title, action, key) in [
      (String(localized: "Zoom In"), #selector(zoomIn(_:)), "="),
      (String(localized: "Zoom Out"), #selector(zoomOut(_:)), "-"),
      (String(localized: "Actual Size"), #selector(resetZoom(_:)), "0"),
      (String(localized: "Word Wrap"), #selector(toggleWordWrap(_:)), ""),
    ] {
      view.addItem(withTitle: title, action: action, keyEquivalent: key).target = self
    }
    viewItem.submenu = view

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
    windowMenu.addItem(.separator())
    for (title, action, key) in [
      (String(localized: "Move Tab Left"), #selector(moveTabLeft(_:)), "["),
      (String(localized: "Move Tab Right"), #selector(moveTabRight(_:)), "]"),
    ] {
      let item = windowMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
      item.target = self
      item.keyEquivalentModifierMask = [.command, .control, .shift]
    }
    let allTabs = windowMenu.addItem(
      withTitle: String(localized: "All Tabs"), action: #selector(showAllTabs(_:)),
      keyEquivalent: "t")
    allTabs.target = self
    allTabs.keyEquivalentModifierMask = [.command, .shift, .option]
    windowItem.submenu = windowMenu
    return main
  }
}
