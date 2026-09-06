import AppKit
import NoteHushCore
import UniformTypeIdentifiers

@MainActor
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate {
  private(set) var tabs: [EditorTab] = []
  private var selectedID: UUID?
  private var revision: UInt64 = 0
  private var ready = false
  private var stopping = false
  private let store: RecoveryStore
  private var coordinator: CheckpointCoordinator?
  private let editorHost = NSView()
  private let tabStack = NSStackView()
  private let tabScroll = NSScrollView()
  private let banner = NSStackView()
  private let message = NSTextField(wrappingLabelWithString: "")
  private let newButton = NSButton()
  private var startupWarning: String?
  private var loadingTask: Task<Void, Never>?
  private var loading = false
  let fileService: any TextFileAccess
  var openingTask: Task<Void, Never>?
  var pendingFileURLs: [URL] = []
  var savingTask: Task<Void, Never>?
  var filePanel: NSSavePanel?
  var resolutionAlert: NSAlert?
  private let fileBanner = NSStackView()
  private let fileMessage = NSTextField(wrappingLabelWithString: "")
  private let cancelOpeningButton = NSButton()
  var canEditFiles: Bool { ready && !stopping }
  var selectedTab: EditorTab? { tabs.first { $0.id == selectedID } }

  convenience init(directory: URL) {
    self.init(store: RecoveryStore(directory: directory))
  }

  init(store: RecoveryStore, fileService: any TextFileAccess = TextFileService()) {
    self.store = store
    self.fileService = fileService
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.title = "NoteHush"
    window.minSize = NSSize(width: 420, height: 300)
    window.tabbingMode = .disallowed
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
    window.delegate = self
    buildInterface()
    showWarning(String(localized: "Restoring your workspace…"))
    newButton.isEnabled = false
    loadingTask = Task { [weak self] in await self?.loadWorkspace() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func waitUntilLoaded() async { await loadingTask?.value }

  func installFile(_ opened: OpenedTextFile, grantedURL: URL) {
    guard canEditFiles else { return }
    if let existing = tabs.first(where: {
      $0.file?.identity == opened.binding.identity || $0.file?.url == opened.binding.url
    }) {
      existing.relocate(using: opened.binding, grantedURL: grantedURL)
      select(existing.id)
      return
    }
    let tab = makeTab(
      TabSnapshot(
        title: opened.binding.url.lastPathComponent,
        text: opened.text, file: opened.binding))
    tab.grantAccess(to: grantedURL)
    tabs.append(tab)
    select(tab.id)
  }

  func didSaveFile() {
    updateTabTitles()
    coordinator?.changed(immediate: true)
  }

  func showFileMessage(_ text: String?, opening: Bool = false) {
    fileMessage.stringValue = text ?? ""
    cancelOpeningButton.isHidden = !opening
    fileBanner.isHidden = text == nil
  }

  @objc private func dismissFileMessage(_ sender: Any?) { showFileMessage(nil) }
  @objc func cancelOpening(_ sender: Any?) {
    pendingFileURLs.removeAll()
    openingTask?.cancel()
    showFileMessage(String(localized: "Opening cancelled. Existing drafts are unchanged."))
  }

  private func loadWorkspace() async {
    guard !ready, !loading else { return }
    loading = true
    defer { loading = false }
    do {
      let loaded = try await store.load()
      guard !stopping else { return }
      let snapshot = loaded.snapshot ?? .empty()
      guard snapshot.revision < UInt64.max else { throw RecoveryError.staleRevision }
      revision = snapshot.revision
      tabs = snapshot.tabs.map { makeTab($0) }
      selectedID = snapshot.selectedTabID
      restoreWindowFrame(snapshot.windowFrame)
      ready = true
      newButton.isEnabled = true
      if loaded.foundDamagedGeneration || loaded.source == .previous {
        startupWarning = String(
          localized:
            "A recovery copy was used. Some recent edits may be missing; original recovery files are preserved."
        )
      }
      coordinator = CheckpointCoordinator(
        store: store, snapshot: { [unowned self] in captureSnapshot() },
        report: { [weak self] error in self?.report(error) })
      rebuildTabs()
      showWarning(startupWarning)
      presentSelectedTab()
      coordinator?.changed(immediate: true)
    } catch {
      guard !stopping else { return }
      if case .unsupportedSchema = error as? RecoveryError {
        showWarning(
          String(
            localized:
              "This workspace was saved by a newer NoteHush. Editing is disabled to protect it. Update the app, retry, or export the recovery files."
          ))
      } else {
        showWarning(
          String(
            localized:
              "Your workspace could not be restored. Editing is disabled to protect existing drafts. Retry or export the recovery files."
          ))
      }
    }
  }

  @objc func newTab(_ sender: Any?) {
    guard ready, !stopping else { return }
    let tab = makeTab(TabSnapshot(title: String(localized: "Untitled \(tabs.count + 1)")))
    tabs.append(tab)
    select(tab.id)
  }

  @objc func nextTab(_ sender: Any?) { stepTab(1) }
  @objc func previousTab(_ sender: Any?) { stepTab(-1) }

  private func stepTab(_ delta: Int) {
    guard let index = tabs.firstIndex(where: { $0.id == selectedID }), tabs.count > 1 else {
      return
    }
    select(tabs[(index + delta + tabs.count) % tabs.count].id)
  }

  @objc private func tabClicked(_ sender: NSButton) {
    guard let identifier = sender.identifier, let id = UUID(uuidString: identifier.rawValue) else {
      return
    }
    select(id)
  }

  private func select(_ id: UUID) {
    guard ready, !stopping else { return }
    if let old = tabs.first(where: { $0.id == selectedID }) {
      _ = old.snapshot(isVisible: true)
      old.suspendScrollObservation()
      old.editor.breakUndoCoalescing()
    }
    selectedID = id
    rebuildTabs()
    presentSelectedTab()
    coordinator?.changed(immediate: true)
  }

  private func makeTab(_ snapshot: TabSnapshot) -> EditorTab {
    let tab = EditorTab(snapshot: snapshot)
    tab.onChange = { [weak self] in
      guard let self, ready, !stopping else { return }
      updateTabTitles()
      coordinator?.changed()
    }
    return tab
  }

  private func presentSelectedTab() {
    guard let tab = tabs.first(where: { $0.id == selectedID }) else { return }
    tab.suspendScrollObservation()
    for view in editorHost.subviews { view.removeFromSuperview() }
    editorHost.addSubview(tab.scrollView)
    NSLayoutConstraint.activate([
      tab.scrollView.leadingAnchor.constraint(equalTo: editorHost.leadingAnchor),
      tab.scrollView.trailingAnchor.constraint(equalTo: editorHost.trailingAnchor),
      tab.scrollView.topAnchor.constraint(equalTo: editorHost.topAnchor),
      tab.scrollView.bottomAnchor.constraint(equalTo: editorHost.bottomAnchor),
    ])
    window?.contentView?.layoutSubtreeIfNeeded()
    window?.makeFirstResponder(tab.editor)
    tab.restoreScroll()
    if let button = tabStack.arrangedSubviews.first(where: {
      $0.identifier?.rawValue == tab.id.uuidString
    }) {
      tabStack.scrollToVisible(button.frame)
    }
  }

  private func captureSnapshot() -> WorkspaceSnapshot {
    if revision < UInt64.max { revision += 1 }
    let frame = window?.frame ?? .zero
    return WorkspaceSnapshot(
      revision: revision, tabs: tabs.map { $0.snapshot(isVisible: $0.id == selectedID) },
      selectedTabID: selectedID ?? tabs[0].id,
      windowFrame: WindowFrame(
        x: frame.minX, y: frame.minY, width: frame.width, height: frame.height))
  }

  func prepareToQuit() async {
    guard !stopping else {
      await coordinator?.shutdown()
      return
    }
    stopping = true
    pendingFileURLs.removeAll()
    openingTask?.cancel()
    // Use the panel's cancellation path so its completion resumes Save As.
    filePanel?.cancel(nil)
    if let resolutionAlert { window?.endSheet(resolutionAlert.window, returnCode: .abort) }
    newButton.isEnabled = false
    for tab in tabs {
      tab.editor.unmarkText()
      tab.editor.isEditable = false
    }
    await loadingTask?.value
    await savingTask?.value
    await coordinator?.shutdown()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApplication.shared.terminate(nil)
    return false
  }

  func windowDidMove(_ notification: Notification) { geometryChanged() }
  func windowDidResize(_ notification: Notification) { geometryChanged() }

  private func geometryChanged() {
    guard ready, !stopping else { return }
    coordinator?.changed()
  }

  private func restoreWindowFrame(_ saved: WindowFrame?) {
    guard let saved, saved.isValid, let window else { return }
    let proposed = NSRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height)
    let screen =
      NSScreen.screens.max {
        let a = $0.visibleFrame.intersection(proposed)
        let b = $1.visibleFrame.intersection(proposed)
        return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
      } ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return }
    let width = min(max(saved.width, window.minSize.width), visible.width)
    let height = min(max(saved.height, window.minSize.height), visible.height)
    window.setFrame(
      NSRect(
        x: min(max(saved.x, visible.minX), visible.maxX - width),
        y: min(max(saved.y, visible.minY), visible.maxY - height), width: width, height: height),
      display: true)
  }

  private func report(_ error: RecoveryError?) {
    if error != nil {
      showWarning(
        String(
          localized:
            "Draft recovery could not be saved. Keep this window open and retry, or export your drafts before quitting."
        ))
    } else {
      showWarning(startupWarning)
    }
  }

  private func showWarning(_ text: String?) {
    message.stringValue = text ?? ""
    banner.isHidden = text == nil
  }

  @objc private func retryRecovery(_ sender: Any?) {
    guard !stopping else { return }
    if ready {
      coordinator?.retry()
    } else {
      loadingTask = Task { [weak self] in await self?.loadWorkspace() }
    }
  }

  @objc private func exportRecovery(_ sender: Any?) {
    guard !stopping, let window else { return }
    let panel = NSSavePanel()
    panel.preventsApplicationTerminationWhenModal = false
    panel.title = String(localized: "Export Recovery")
    panel.message =
      ready
      ? String(localized: "Export all open drafts, including their text, as a JSON recovery file.")
      : String(localized: "Export the original recovery generations without changing them.")
    panel.nameFieldStringValue = ready ? "NoteHush-Drafts.json" : "NoteHush-Recovery.json"
    panel.allowedContentTypes = [.json]
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let url = panel.url, let self else { return }
      let snapshot = ready ? captureSnapshot() : nil
      Task {
        do {
          let data: Data
          if let snapshot {
            data = try await Task.detached {
              let encoder = JSONEncoder()
              encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
              return try encoder.encode(snapshot)
            }.value
          } else {
            data = try await store.exportGenerations()
          }
          try await Task.detached { try data.write(to: url, options: .atomic) }.value
        } catch {
          showWarning(
            String(
              localized:
                "Export failed. Your drafts are still here. Retry or choose another destination."))
        }
      }
    }
  }

  private func rebuildTabs() {
    for view in tabStack.arrangedSubviews {
      tabStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    for tab in tabs {
      let button = NSButton(title: tab.title, target: self, action: #selector(tabClicked(_:)))
      button.setButtonType(.pushOnPushOff)
      button.bezelStyle = .recessed
      button.identifier = NSUserInterfaceItemIdentifier(tab.id.uuidString)
      button.setAccessibilityIdentifier("tab-\(tab.id.uuidString)")
      button.setAccessibilityRole(.radioButton)
      button.setAccessibilityRoleDescription(String(localized: "tab"))
      button.state = tab.id == selectedID ? .on : .off
      tabStack.addArrangedSubview(button)
    }
    updateTabTitles()
  }

  private func updateTabTitles() {
    for (tab, view) in zip(tabs, tabStack.arrangedSubviews) {
      guard let button = view as? NSButton else { continue }
      button.title = tab.title + (tab.isDirty ? " •" : "")
      button.setAccessibilityLabel(
        tab.title + (tab.isDirty ? String(localized: ", unsaved changes") : ""))
    }
  }

  private func buildInterface() {
    let root = NSStackView()
    root.orientation = .vertical
    root.spacing = 0
    root.alignment = .leading
    window?.contentView = root
    let bar = NSStackView()
    bar.spacing = 8
    bar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    tabStack.orientation = .horizontal
    tabStack.spacing = 4
    tabStack.translatesAutoresizingMaskIntoConstraints = false
    tabScroll.drawsBackground = false
    tabScroll.hasHorizontalScroller = true
    tabScroll.autohidesScrollers = true
    tabScroll.documentView = tabStack
    newButton.title = "+"
    newButton.bezelStyle = .texturedRounded
    newButton.target = self
    newButton.action = #selector(newTab(_:))
    newButton.toolTip = String(localized: "New Tab (⌘N)")
    newButton.setAccessibilityLabel(String(localized: "New Tab"))
    newButton.setAccessibilityIdentifier("new-tab")
    bar.addArrangedSubview(tabScroll)
    bar.addArrangedSubview(newButton)
    banner.orientation = .horizontal
    banner.spacing = 12
    banner.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    message.setAccessibilityIdentifier("recovery-message")
    message.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    banner.addArrangedSubview(message)
    banner.addArrangedSubview(
      NSButton(
        title: String(localized: "Retry"), target: self, action: #selector(retryRecovery(_:))))
    banner.addArrangedSubview(
      NSButton(
        title: String(localized: "Export…"), target: self, action: #selector(exportRecovery(_:))))
    fileBanner.orientation = .horizontal
    fileBanner.spacing = 12
    fileBanner.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    fileMessage.setAccessibilityIdentifier("file-message")
    fileMessage.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    cancelOpeningButton.title = String(localized: "Cancel Opening")
    cancelOpeningButton.target = self
    cancelOpeningButton.action = #selector(cancelOpening(_:))
    fileBanner.addArrangedSubview(fileMessage)
    fileBanner.addArrangedSubview(cancelOpeningButton)
    fileBanner.addArrangedSubview(
      NSButton(
        title: String(localized: "Dismiss"), target: self, action: #selector(dismissFileMessage(_:))
      ))
    fileBanner.isHidden = true
    for view in [bar, banner, fileBanner, editorHost] {
      root.addArrangedSubview(view)
      view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
    NSLayoutConstraint.activate([
      bar.heightAnchor.constraint(equalToConstant: 42),
      tabScroll.heightAnchor.constraint(equalToConstant: 34),
      tabStack.leadingAnchor.constraint(equalTo: tabScroll.contentView.leadingAnchor),
      tabStack.topAnchor.constraint(equalTo: tabScroll.contentView.topAnchor),
      tabStack.heightAnchor.constraint(equalToConstant: 30),
      newButton.widthAnchor.constraint(equalToConstant: 32),
    ])
  }
}
