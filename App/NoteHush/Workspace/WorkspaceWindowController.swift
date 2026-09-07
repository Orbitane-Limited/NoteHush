import AppKit
import NoteHushCore
import UniformTypeIdentifiers

@MainActor
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate {
  private(set) var tabs: [EditorTab] = []
  private var selectedID: UUID?
  private var revision: UInt64 = 0
  private var ready = false
  #if NOTEHUSH_PERFORMANCE_TESTING
    private var performancePresentationComplete = false
  #endif
  private var stopping = false
  private let store: RecoveryStore
  private var coordinator: CheckpointCoordinator?
  private let editorHost = NSView()
  let tabBar = TabBarView()
  private(set) var closedTabs: [ClosedTabSnapshot] = []
  private let banner = NSStackView()
  private let message = NSTextField(wrappingLabelWithString: "")
  private let newButton = NSButton()
  private var startupWarning: String?
  private var loadingTask: Task<Void, Never>?
  private var loading = false
  let fileService: any TextFileAccess
  var openingTask: Task<Void, Never>?
  var pendingFileURLs: [URL] = []
  var savingTask: Task<Void, Never>? {
    didSet { if ready { updateTabTitles() } }
  }
  var filePanel: NSSavePanel?
  var resolutionAlert: NSAlert?
  var navigationSheet: GoToLineSheet?
  var navigationTask: Task<Void, Never>?
  private(set) var preferences = EditorPreferences()
  private var preferencesWindow: PreferencesWindowController?
  let printer = WorkspacePrinter()
  private let statusView = EditorStatusView()
  private let fileBanner = NSStackView()
  private let fileMessage = NSTextField(wrappingLabelWithString: "")
  private let cancelOpeningButton = NSButton()
  var canEditFiles: Bool { ready && !stopping }
  var canManageTabs: Bool { canNavigate && savingTask == nil }
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
    printer.onFailure = { [weak self] in
      self?.showFileMessage(
        String(
          localized:
            "The text does not fit this page setup. Choose a larger paper size, reduce print scaling or use a smaller font."
        ))
    }
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
      preferences = (snapshot.preferences ?? EditorPreferences()).normalized
      window?.appearance = preferences.appKitAppearance
      tabs = snapshot.tabs.map { makeTab($0) }
      closedTabs = snapshot.closedTabs ?? []
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
      #if NOTEHUSH_PERFORMANCE_TESTING
        performancePresentationComplete = true
        WorkspacePerformanceProbe.editorReady(window: window, editor: selectedTab?.editor)
      #endif
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
    guard canNavigate else { return }
    let tab = makeTab(TabSnapshot(title: String(localized: "Untitled \(tabs.count + 1)")))
    tabs.append(tab)
    select(tab.id)
  }

  @objc func nextTab(_ sender: Any?) { stepTab(1) }
  @objc func previousTab(_ sender: Any?) { stepTab(-1) }

  private func stepTab(_ delta: Int) {
    guard canNavigate, let index = tabs.firstIndex(where: { $0.id == selectedID }), tabs.count > 1
    else {
      return
    }
    select(tabs[(index + delta + tabs.count) % tabs.count].id)
  }

  private func select(_ id: UUID) {
    guard canEditFiles, tabs.contains(where: { $0.id == id }) else { return }
    if selectedID == id {
      updateTabTitles()
      window?.makeFirstResponder(selectedTab?.editor)
      tabBar.reveal(id)
      return
    }
    if let old = tabs.first(where: { $0.id == selectedID }) {
      _ = old.snapshot(isVisible: true)
      old.suspendScrollObservation()
      old.deactivateStatus()
      old.editor.breakUndoCoalescing()
    }
    selectedID = id
    rebuildTabs()
    presentSelectedTab()
    coordinator?.changed(immediate: true)
  }

  private func makeTab(_ snapshot: TabSnapshot) -> EditorTab {
    let tab = EditorTab(snapshot: snapshot, preferences: preferences)
    tab.onChange = { [weak self] in
      guard let self, ready, !stopping else { return }
      updateTabTitles()
      coordinator?.changed()
    }
    tab.onStatusChange = { [weak self, id = tab.id] in
      guard let self, selectedID == id else { return }
      statusView.render(selectedTab)
      navigationSheet?.update(lineCount: selectedTab?.metrics?.lineCount)
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
    tab.activateStatus()
    statusView.render(tab)
    tabBar.reveal(tab.id)
  }

  private func captureSnapshot() -> WorkspaceSnapshot {
    if revision < UInt64.max { revision += 1 }
    let frame = window?.frame ?? .zero
    return WorkspaceSnapshot(
      revision: revision, tabs: tabs.map { $0.snapshot(isVisible: $0.id == selectedID) },
      selectedTabID: selectedID ?? tabs[0].id,
      windowFrame: WindowFrame(
        x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
      preferences: preferences, closedTabs: closedTabs)
  }

  func showPreferences() {
    guard canNavigate else { return }
    if preferencesWindow == nil {
      preferencesWindow = PreferencesWindowController(preferences: preferences) {
        [weak self] value in
        self?.applyPreferences(value)
      }
    }
    preferencesWindow?.showWindow(nil)
    preferencesWindow?.window?.makeKeyAndOrderFront(nil)
  }

  func applyPreferences(_ value: EditorPreferences) {
    guard canEditFiles else { return }
    preferences = value.normalized
    window?.appearance = preferences.appKitAppearance
    for tab in tabs { tab.applyPreferences(preferences) }
    preferencesWindow?.refresh(preferences)
    coordinator?.changed()
  }

  func prepareToQuit() async {
    guard !stopping else {
      await coordinator?.shutdown()
      return
    }
    // Commit a pending settings field edit before freezing and checkpointing.
    preferencesWindow?.window?.makeFirstResponder(nil)
    preferencesWindow?.close()
    stopping = true
    printer.cancelSheets(on: window)
    pendingFileURLs.removeAll()
    openingTask?.cancel()
    // Use the panel's cancellation path so its completion resumes Save As.
    filePanel?.cancel(nil)
    if let resolutionAlert { window?.endSheet(resolutionAlert.window, returnCode: .abort) }
    newButton.isEnabled = false
    for tab in tabs {
      tab.deactivateStatus()
      tab.editor.unmarkText()
      tab.editor.isEditable = false
    }
    await loadingTask?.value
    await savingTask?.value
    await navigationTask?.value
    await coordinator?.shutdown()
  }

  func presentResolutionAlert(_ alert: NSAlert, initialResponder: NSResponder? = nil) async
    -> NSApplication.ModalResponse
  {
    guard let window, canEditFiles, window.attachedSheet == nil else { return .abort }
    alert.window.preventsApplicationTerminationWhenModal = false
    resolutionAlert = alert
    defer { resolutionAlert = nil }
    return await withCheckedContinuation { continuation in
      alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
      if let initialResponder { alert.window.makeFirstResponder(initialResponder) }
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApplication.shared.terminate(nil)
    return false
  }

  func windowDidMove(_ notification: Notification) { geometryChanged() }
  func windowDidResize(_ notification: Notification) { geometryChanged() }

  #if NOTEHUSH_PERFORMANCE_TESTING
    func windowDidBecomeKey(_ notification: Notification) {
      // Activation can finish after recovery. Report readiness only once both
      // the restored editor and the actual keyboard destination are established.
      guard performancePresentationComplete else { return }
      WorkspacePerformanceProbe.editorReady(window: window, editor: selectedTab?.editor)
    }
  #endif

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
      ? String(
        localized:
          "Export open and recently closed drafts, including their text, as a JSON recovery file.")
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

  private func rebuildTabs() { tabBar.update(tabs, selectedID: selectedID) }

  private func updateTabTitles() { tabBar.update(tabs, selectedID: selectedID) }

  func closeTab(_ id: UUID) {
    guard canManageTabs, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    let tab = tabs[index]
    tab.editor.unmarkText()
    let snapshot = tab.snapshot(isVisible: id == selectedID)
    tab.prepareForClose()
    closedTabs.insert(ClosedTabSnapshot(tab: snapshot, originalIndex: index), at: 0)
    closedTabs = Array(closedTabs.prefix(ClosedTabSnapshot.limit))
    tabs.remove(at: index)
    if tabs.isEmpty { tabs.append(makeTab(TabSnapshot())) }
    if selectedID == id {
      selectedID = tabs[min(index, tabs.count - 1)].id
      rebuildTabs()
      presentSelectedTab()
    } else {
      rebuildTabs()
      if let selectedID { tabBar.reveal(selectedID) }
    }
    coordinator?.changed(immediate: true)
  }

  func closeSelectedTab() {
    if let selectedID { closeTab(selectedID) }
  }

  func reopenClosedTab() {
    guard canManageTabs, !closedTabs.isEmpty else { return }
    var record = closedTabs.removeFirst()
    if let file = record.tab.file,
      tabs.contains(where: { $0.file?.identity == file.identity || $0.file?.url == file.url })
    {
      // Preserve the closed text as an independent draft; never replace the open buffer.
      record.tab.file = nil
      showFileMessage(
        String(
          localized:
            "This file is already open. The closed version was reopened as a separate draft; use Save As to keep it."
        ))
    }
    let tab = makeTab(record.tab)
    tabs.insert(tab, at: min(record.originalIndex, tabs.count))
    select(tab.id)
  }

  func clearClosedTabs() {
    guard canManageTabs, !closedTabs.isEmpty else { return }
    closedTabs.removeAll()
    coordinator?.changed(immediate: true)
  }

  func moveTab(_ id: UUID, to index: Int) {
    guard canManageTabs, let old = tabs.firstIndex(where: { $0.id == id }),
      tabs.indices.contains(index), old != index
    else { return }
    tabs.insert(tabs.remove(at: old), at: index)
    rebuildTabs()
    if let selectedID { tabBar.reveal(selectedID) }
    coordinator?.changed(immediate: true)
  }

  func canMoveSelectedTab(by delta: Int) -> Bool {
    guard canManageTabs, let index = tabs.firstIndex(where: { $0.id == selectedID }) else {
      return false
    }
    return tabs.indices.contains(index + delta)
  }

  func moveSelectedTab(by delta: Int) {
    guard canMoveSelectedTab(by: delta),
      let index = tabs.firstIndex(where: { $0.id == selectedID })
    else { return }
    moveTab(tabs[index].id, to: index + delta)
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
    tabBar.onSelect = { [weak self] id in
      guard let self else { return }
      guard canNavigate else {
        updateTabTitles()
        return
      }
      select(id)
    }
    tabBar.onClose = { [weak self] id in self?.closeTab(id) }
    tabBar.onMove = { [weak self] id, index in self?.moveTab(id, to: index) }
    tabBar.canManage = { [weak self] in self?.canManageTabs == true }
    newButton.title = "+"
    newButton.bezelStyle = .texturedRounded
    newButton.target = self
    newButton.action = #selector(newTab(_:))
    newButton.toolTip = String(localized: "New Tab (⌘N)")
    newButton.setAccessibilityLabel(String(localized: "New Tab"))
    newButton.setAccessibilityIdentifier("new-tab")
    bar.addArrangedSubview(tabBar)
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
    for view in [bar, banner, fileBanner, editorHost, statusView] {
      root.addArrangedSubview(view)
      view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
    NSLayoutConstraint.activate([
      bar.heightAnchor.constraint(equalToConstant: 42),
      tabBar.heightAnchor.constraint(equalToConstant: 34),
      newButton.widthAnchor.constraint(equalToConstant: 32),
    ])
  }
}
