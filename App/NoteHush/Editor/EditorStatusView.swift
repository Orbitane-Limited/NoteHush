import AppKit
import NoteHushCore

@MainActor
final class EditorStatusView: NSView {
  private let position = NSTextField(wrappingLabelWithString: "")
  private let counts = NSTextField(wrappingLabelWithString: "")
  private let format = NSTextField(wrappingLabelWithString: "")

  init() {
    super.init(frame: .zero)
    let layout = NSStackView()
    layout.orientation = .vertical
    layout.spacing = 0
    let separator = NSBox()
    separator.boxType = .separator
    layout.addArrangedSubview(separator)
    let row = NSStackView(views: [position, counts, format])
    row.spacing = 16
    row.alignment = .centerY
    row.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
    row.setAccessibilityElement(false)
    layout.addArrangedSubview(row)
    addSubview(layout)
    layout.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      layout.leadingAnchor.constraint(equalTo: leadingAnchor),
      layout.trailingAnchor.constraint(equalTo: trailingAnchor),
      layout.topAnchor.constraint(equalTo: topAnchor),
      layout.bottomAnchor.constraint(equalTo: bottomAnchor),
      separator.widthAnchor.constraint(equalTo: layout.widthAnchor),
      row.widthAnchor.constraint(equalTo: layout.widthAnchor),
    ])
    for (label, identifier) in [
      (position, "status-position"), (counts, "status-counts"),
      (format, "status-format"),
    ] {
      // Set these explicitly so the status remains queryable as static text
      // across AppKit versions and hardware architectures.
      label.setAccessibilityElement(true)
      label.setAccessibilityRole(.staticText)
      label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
      label.setAccessibilityIdentifier(identifier)
      label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    counts.setContentHuggingPriority(.defaultLow, for: .horizontal)
    // Use a plain NSView group to keep NSStackView's accessibility behavior
    // from replacing this explicit child list on some AppKit versions.
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel(String(localized: "Document status"))
    setAccessibilityChildren([position, counts, format])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func render(_ tab: EditorTab?) {
    guard let tab else {
      position.stringValue = ""
      counts.stringValue = ""
      format.stringValue = ""
      return
    }
    let encoding = tab.file?.encoding.displayName ?? TextFileEncoding.utf8.displayName
    guard let metrics = tab.metrics else {
      position.stringValue = String(localized: "Ln —, Col —")
      counts.stringValue = String(localized: "Updating…")
      format.stringValue = encoding
      format.toolTip = nil
      format.setAccessibilityHelp(nil)
      return
    }
    let range = tab.editor.selectedRange()
    let location = metrics.position(atUTF16Offset: range.location)
    position.stringValue = String(localized: "Ln \(location.line), Col \(location.column)")
    let selected = metrics.selectedCharacterCount(
      in: TextSelection(location: range.location, length: range.length))
    counts.stringValue = String(
      localized: "Characters: \(metrics.characterCount) · Selected: \(selected)")
    let newline: String
    switch metrics.newlineKinds.count {
    case 0: newline = String(localized: "No newlines")
    case 1: newline = metrics.newlineKinds.first?.rawValue ?? ""
    default: newline = String(localized: "Mixed")
    }
    format.stringValue = "\(encoding) · \(newline)"
    let kinds = TextNewline.allCases.filter { metrics.newlineKinds.contains($0) }
      .map(\.rawValue).joined(separator: ", ")
    format.toolTip = kinds.isEmpty ? format.stringValue : "\(encoding) · \(kinds)"
    format.setAccessibilityHelp(format.toolTip)
    position.toolTip = String(
      localized:
        "Line and column at the start of the selection. Columns count characters, not screen width."
    )
    counts.toolTip = String(
      localized:
        "Emoji and combined characters count as one character. Line breaks count as characters; CRLF counts as one."
    )
  }
}
