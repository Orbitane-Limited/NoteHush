import AppKit
import NoteHushCore

@MainActor
final class PreferencesWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
  private var preferences: EditorPreferences
  private let onChange: (EditorPreferences) -> Void
  private let family = NSPopUpButton()
  private let face = NSPopUpButton()
  private let size = NSTextField()
  private let appearance = NSPopUpButton()
  private let zoom = NSPopUpButton()
  private let wrap = NSButton(
    checkboxWithTitle: String(localized: "Wrap long lines"), target: nil, action: nil)
  private let spelling = NSButton(
    checkboxWithTitle: String(localized: "Check spelling while typing"), target: nil, action: nil)
  private var faceNames: [String] = []
  private var publishingChange = false

  init(preferences: EditorPreferences, onChange: @escaping (EditorPreferences) -> Void) {
    self.preferences = preferences
    self.onChange = onChange
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = String(localized: "Settings")
    window.tabbingMode = .disallowed
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
    window.delegate = self
    buildInterface()
    refresh(preferences)
    window.initialFirstResponder = family
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func showWindow(_ sender: Any?) {
    super.showWindow(sender)
    window?.makeFirstResponder(family)
  }

  func windowWillClose(_ notification: Notification) {
    guard let window, !window.makeFirstResponder(nil) else { return }
    // Invalid numeric input must not keep Settings open or survive invisibly
    // in its field editor. A valid edit already committed through the delegate.
    window.endEditing(for: size)
    size.doubleValue = preferences.fontSize
  }

  func refresh(_ value: EditorPreferences) {
    guard !publishingChange else { return }
    preferences = value.normalized
    window?.appearance = preferences.appKitAppearance
    let selectedFamily =
      preferences.fontName == nil ? nil : preferences.font(zoomed: false).familyName
    family.selectItem(at: 0)
    if let selectedFamily { family.selectItem(withTitle: selectedFamily) }
    rebuildFaces()
    size.doubleValue = preferences.fontSize
    appearance.selectItem(
      at: EditorPreferences.Appearance.allCases.firstIndex(of: preferences.appearance) ?? 0)
    zoom.removeAllItems()
    let steps = Set(EditorPreferences.zoomSteps + [preferences.zoomPercent]).sorted()
    for step in steps {
      zoom.addItem(withTitle: String(localized: "\(step)%"))
      zoom.lastItem?.tag = step
    }
    zoom.selectItem(withTag: preferences.zoomPercent)
    wrap.state = preferences.wordWrap ? .on : .off
    spelling.state = preferences.checksSpelling ? .on : .off
  }

  private func rebuildFaces() {
    face.removeAllItems()
    faceNames.removeAll()
    if family.indexOfSelectedItem == 0 {
      face.addItem(withTitle: String(localized: "Regular"))
      face.isEnabled = false
      return
    }
    face.isEnabled = true
    let members =
      NSFontManager.shared.availableMembers(ofFontFamily: family.titleOfSelectedItem ?? "") ?? []
    for member in members {
      guard member.count >= 2, let name = member[0] as? String, let title = member[1] as? String
      else { continue }
      faceNames.append(name)
      face.addItem(withTitle: title)
    }
    if let name = preferences.fontName, let index = faceNames.firstIndex(of: name) {
      face.selectItem(at: index)
    }
  }

  @objc private func changeFamily(_ sender: Any?) {
    preferences.fontName =
      family.indexOfSelectedItem == 0
      ? nil
      : NSFontManager.shared.font(
        withFamily: family.titleOfSelectedItem ?? "", traits: [], weight: 5,
        size: preferences.fontSize)?.fontName
    rebuildFaces()
    commit()
  }

  @objc private func changeFace(_ sender: Any?) {
    guard faceNames.indices.contains(face.indexOfSelectedItem) else { return }
    preferences.fontName = faceNames[face.indexOfSelectedItem]
    commit()
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard let number = size.objectValue as? NSNumber else {
      size.doubleValue = preferences.fontSize
      return
    }
    preferences.fontSize = number.doubleValue
    preferences = preferences.normalized
    size.doubleValue = preferences.fontSize
    commit()
  }

  @objc private func changeAppearance(_ sender: Any?) {
    let values = EditorPreferences.Appearance.allCases
    guard values.indices.contains(appearance.indexOfSelectedItem) else { return }
    preferences.appearance = values[appearance.indexOfSelectedItem]
    commit()
  }

  @objc private func changeZoom(_ sender: Any?) {
    preferences.zoomPercent = zoom.selectedTag()
    commit()
  }

  @objc private func changeWrap(_ sender: Any?) {
    preferences.wordWrap = wrap.state == .on
    commit()
  }

  @objc private func changeSpelling(_ sender: Any?) {
    preferences.checksSpelling = spelling.state == .on
    commit()
  }

  private func commit() {
    preferences = preferences.normalized
    // Finishing a field edit can precede a popup's action. A full refresh here
    // would reset the popup's pending selection (including through onChange).
    // User actions update their own controls; external changes still use refresh.
    publishingChange = true
    onChange(preferences)
    publishingChange = false
    window?.appearance = preferences.appKitAppearance
  }

  private func buildInterface() {
    family.addItem(withTitle: String(localized: "System Monospaced"))
    family.addItems(
      withTitles: NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
      })
    for (control, action, identifier, label) in [
      (family, #selector(changeFamily(_:)), "font-family", String(localized: "Font family")),
      (face, #selector(changeFace(_:)), "font-face", String(localized: "Font face")),
      (appearance, #selector(changeAppearance(_:)), "appearance", String(localized: "Appearance")),
      (zoom, #selector(changeZoom(_:)), "zoom", String(localized: "Zoom")),
    ] {
      control.target = self
      control.action = action
      control.setAccessibilityIdentifier(identifier)
      control.setAccessibilityLabel(label)
      control.widthAnchor.constraint(equalToConstant: 270).isActive = true
    }
    appearance.addItems(withTitles: [
      String(localized: "System"), String(localized: "Light"), String(localized: "Dark"),
    ])
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimum = 8
    formatter.maximum = 72
    formatter.maximumFractionDigits = 2
    size.formatter = formatter
    size.delegate = self
    size.setAccessibilityIdentifier("font-size")
    size.setAccessibilityLabel(String(localized: "Font size in points, 8 to 72"))
    size.widthAnchor.constraint(equalToConstant: 80).isActive = true
    wrap.target = self
    wrap.action = #selector(changeWrap(_:))
    wrap.setAccessibilityIdentifier("word-wrap")
    spelling.target = self
    spelling.action = #selector(changeSpelling(_:))
    spelling.setAccessibilityIdentifier("check-spelling")
    let grid = NSGridView(views: [
      [NSTextField(labelWithString: String(localized: "Font:")), family],
      [NSTextField(labelWithString: String(localized: "Face:")), face],
      [NSTextField(labelWithString: String(localized: "Size (pt):")), size],
      [NSTextField(labelWithString: String(localized: "Appearance:")), appearance],
      [NSTextField(labelWithString: String(localized: "Zoom:")), zoom],
      [NSGridCell.emptyContentView, wrap],
      [NSGridCell.emptyContentView, spelling],
    ])
    grid.rowSpacing = 12
    grid.columnSpacing = 16
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).xPlacement = .leading
    grid.yPlacement = .center
    let help = NSTextField(
      wrappingLabelWithString: String(
        localized:
          "Applies to all tabs. Zoom changes the screen only. Printing uses the chosen font size and wraps to the page."
      ))
    help.textColor = .secondaryLabelColor
    help.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    let root = NSStackView(views: [grid, help])
    root.orientation = .vertical
    root.alignment = .leading
    root.spacing = 20
    root.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
    window?.contentView = root
    help.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48).isActive = true
    family.nextKeyView = face
    face.nextKeyView = size
    size.nextKeyView = appearance
    appearance.nextKeyView = zoom
    zoom.nextKeyView = wrap
    wrap.nextKeyView = spelling
    spelling.nextKeyView = family
  }
}
