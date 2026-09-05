import AppKit
import NoteHushCore

@MainActor
final class WorkspaceWindowController: NSWindowController {
  init() {
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

    let root = NSView()
    window.contentView = root
    let notice = NSTextField(
      wrappingLabelWithString:
        String(localized: "Development preview — drafts are not restored yet."))
    notice.textColor = .secondaryLabelColor
    notice.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    notice.translatesAutoresizingMaskIntoConstraints = false

    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.translatesAutoresizingMaskIntoConstraints = false
    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 580))
    editor.isRichText = false
    editor.importsGraphics = false
    editor.allowsUndo = true
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.isAutomaticTextReplacementEnabled = false
    editor.isAutomaticSpellingCorrectionEnabled = false
    editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
    editor.textContainerInset = NSSize(width: 16, height: 16)
    editor.autoresizingMask = [.width]
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    editor.textContainer?.widthTracksTextView = true
    editor.textContainer?.containerSize = NSSize(
      width: 900, height: CGFloat.greatestFiniteMagnitude)
    editor.setAccessibilityLabel(String(localized: "Note text"))
    editor.string = WorkspaceSnapshot.empty().tabs[0].text
    scroll.documentView = editor
    root.addSubview(notice)
    root.addSubview(scroll)
    NSLayoutConstraint.activate([
      notice.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
      notice.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
      notice.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
      scroll.topAnchor.constraint(equalTo: notice.bottomAnchor, constant: 8),
      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    window.initialFirstResponder = editor
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }
}
