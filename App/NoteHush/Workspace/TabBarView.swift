import AppKit

/// Stable native buttons keep focus when selection or dirty state changes.
@MainActor
final class TabBarView: NSView {
  private let scroll = NSScrollView()
  private let stack = NSStackView()
  private let overflow = NSButton()
  private let insertion = NSBox()
  private var items: [(id: UUID, cell: NSStackView, button: TabButton, close: NSButton)] = []
  var onSelect: ((UUID) -> Void)?
  var onClose: ((UUID) -> Void)?
  var onMove: ((UUID, Int) -> Void)?
  var canManage: (() -> Bool)?

  override init(frame: NSRect) {
    super.init(frame: frame)
    stack.orientation = .horizontal
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroll.drawsBackground = false
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    scroll.documentView = stack
    overflow.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
    overflow.bezelStyle = .texturedRounded
    overflow.target = self
    overflow.action = #selector(showAllTabs(_:))
    overflow.toolTip = String(localized: "All Tabs")
    overflow.setAccessibilityLabel(String(localized: "All Tabs"))
    overflow.setAccessibilityIdentifier("all-tabs")
    for view in [scroll, overflow] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
      scroll.topAnchor.constraint(equalTo: topAnchor),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
      scroll.trailingAnchor.constraint(equalTo: overflow.leadingAnchor, constant: -4),
      overflow.trailingAnchor.constraint(equalTo: trailingAnchor),
      overflow.centerYAnchor.constraint(equalTo: centerYAnchor),
      overflow.widthAnchor.constraint(equalToConstant: 32),
      stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
      stack.heightAnchor.constraint(equalToConstant: 30),
    ])
    insertion.boxType = .custom
    insertion.borderWidth = 0
    insertion.fillColor = .controlAccentColor
    insertion.isHidden = true
    addSubview(insertion)
    registerForDraggedTypes([TabButton.dragType])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func update(_ tabs: [EditorTab], selectedID: UUID?) {
    let ids = tabs.map(\.id)
    for item in items where !ids.contains(item.id) {
      stack.removeArrangedSubview(item.cell)
      item.cell.removeFromSuperview()
    }
    items = tabs.map { tab in
      if let existing = items.first(where: { $0.id == tab.id }) { return existing }
      let button = TabButton(title: tab.title, target: self, action: #selector(selectTab(_:)))
      button.tabID = tab.id
      button.owner = self
      button.setButtonType(.pushOnPushOff)
      button.bezelStyle = .recessed
      button.lineBreakMode = .byTruncatingTail
      button.focusRingType = .exterior
      button.setAccessibilityIdentifier("tab-\(tab.id.uuidString)")
      button.setAccessibilityRole(.radioButton)
      button.setAccessibilityRoleDescription(String(localized: "tab"))
      let close = NSButton(
        image: NSImage(systemSymbolName: "xmark", accessibilityDescription: nil) ?? NSImage(),
        target: self, action: #selector(closeTab(_:)))
      close.identifier = NSUserInterfaceItemIdentifier(tab.id.uuidString)
      close.isBordered = false
      close.setAccessibilityIdentifier("close-tab-\(tab.id.uuidString)")
      let cell = NSStackView(views: [button, close])
      cell.spacing = 0
      NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: 144),
        close.widthAnchor.constraint(equalToConstant: 24),
      ])
      return (tab.id, cell, button, close)
    }
    // Keep native view and accessibility order aligned. Reuse controls and only
    // restack when identities/order change, never for typing or selection updates.
    let ordered = items.map(\.cell)
    if stack.arrangedSubviews != ordered {
      let focused = window?.firstResponder as? NSView
      let restoreFocus = focused?.isDescendant(of: stack) == true
      for view in stack.arrangedSubviews {
        stack.removeArrangedSubview(view)
        view.removeFromSuperview()
      }
      for cell in ordered { stack.addArrangedSubview(cell) }
      if restoreFocus { window?.makeFirstResponder(focused) }
    }
    for (index, tab) in tabs.enumerated() {
      let item = items[index]
      item.button.title = tab.title + (tab.isDirty ? " •" : "")
      item.button.toolTip = tab.title
      item.button.state = tab.id == selectedID ? .on : .off
      item.button.setAccessibilityLabel(
        tab.title + String(localized: ", tab \(index + 1) of \(tabs.count)")
          + (tab.isDirty ? String(localized: ", unsaved changes") : ""))
      item.close.setAccessibilityLabel(String(localized: "Close \(tab.title)"))
      item.close.toolTip = String(localized: "Close \(tab.title)")
      item.close.isEnabled = canManage?() == true
    }
  }

  func reveal(_ id: UUID) {
    layoutSubtreeIfNeeded()
    if let item = items.first(where: { $0.id == id }) { stack.scrollToVisible(item.cell.frame) }
  }

  @objc private func selectTab(_ sender: TabButton) { onSelect?(sender.tabID) }
  @objc private func closeTab(_ sender: NSButton) {
    guard let value = sender.identifier?.rawValue, let id = UUID(uuidString: value) else { return }
    onClose?(id)
  }

  @objc func showAllTabs(_ sender: Any?) {
    let menu = allTabsMenu()
    menu.popUp(positioning: nil, at: NSPoint(x: overflow.frame.minX, y: 0), in: self)
  }

  func allTabsMenu() -> NSMenu {
    let menu = NSMenu(title: String(localized: "All Tabs"))
    for (index, item) in items.enumerated() {
      let entry = NSMenuItem(
        title: "\(index + 1). \(item.button.title)", action: #selector(chooseTab(_:)),
        keyEquivalent: "")
      entry.target = self
      entry.representedObject = item.id
      entry.state = item.button.state
      menu.addItem(entry)
    }
    return menu
  }

  @objc private func chooseTab(_ sender: NSMenuItem) {
    if let id = sender.representedObject as? UUID { onSelect?(id) }
  }

  private func source(_ sender: any NSDraggingInfo) -> TabButton? {
    guard canManage?() == true, let source = sender.draggingSource as? TabButton,
      source.owner === self,
      sender.draggingPasteboard.string(forType: TabButton.dragType) == source.tabID.uuidString,
      items.contains(where: { $0.id == source.tabID })
    else { return nil }
    return source
  }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    draggingUpdated(sender)
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard source(sender) != nil else { return [] }
    let location = convert(sender.draggingLocation, from: nil)
    guard scroll.frame.contains(location) else {
      insertion.isHidden = true
      return []
    }
    let delta: CGFloat =
      location.x < scroll.frame.minX + 24
      ? -24
      : (location.x > scroll.frame.maxX - 24 ? 24 : 0)
    var bounds = scroll.contentView.bounds
    bounds.origin.x += delta
    scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(bounds).origin)
    scroll.reflectScrolledClipView(scroll.contentView)
    let slot = dropSlot(sender)
    let x = slot < items.count ? items[slot].cell.frame.minX : stack.bounds.maxX
    let point = convert(NSPoint(x: x, y: 0), from: stack)
    insertion.frame = NSRect(x: point.x - 2, y: 3, width: 2, height: 26)
    insertion.isHidden = false
    return .move
  }

  private func dropSlot(_ sender: any NSDraggingInfo) -> Int {
    let x = stack.convert(sender.draggingLocation, from: nil).x
    return items.firstIndex(where: { x < $0.cell.frame.midX }) ?? items.count
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) { insertion.isHidden = true }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    insertion.isHidden = true
    guard let source = source(sender),
      scroll.frame.contains(convert(sender.draggingLocation, from: nil)),
      let old = items.firstIndex(where: { $0.id == source.tabID })
    else { return false }
    let slot = dropSlot(sender)
    onMove?(source.tabID, slot > old ? slot - 1 : slot)
    return true
  }
}

@MainActor
private final class TabButton: NSButton, NSDraggingSource {
  static let dragType = NSPasteboard.PasteboardType("pk.codehub.NoteHush.tab-identity")
  var tabID = UUID()
  weak var owner: TabBarView?

  override func mouseDown(with event: NSEvent) {
    let start = event.locationInWindow
    highlight(true)
    defer { highlight(false) }
    while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      if next.type == .leftMouseUp {
        if bounds.contains(convert(next.locationInWindow, from: nil)) { performClick(nil) }
        return
      }
      let point = next.locationInWindow
      guard hypot(point.x - start.x, point.y - start.y) > 4, owner?.canManage?() == true else {
        continue
      }
      let value = NSPasteboardItem()
      value.setString(tabID.uuidString, forType: Self.dragType)
      let item = NSDraggingItem(pasteboardWriter: value)
      item.setDraggingFrame(
        NSRect(origin: convert(point, from: nil), size: NSSize(width: 24, height: 24)),
        contents: NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil))
      let session = beginDraggingSession(with: [item], event: next, source: self)
      session.animatesToStartingPositionsOnCancelOrFail = false
      return
    }
  }

  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .withinApplication ? .move : []
  }
}
