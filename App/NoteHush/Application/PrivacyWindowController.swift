import AppKit

@MainActor
final class PrivacyWindowController: NSWindowController, NSWindowDelegate {
  private let onClose: () -> Void

  init(onClose: @escaping () -> Void) {
    self.onClose = onClose
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 580),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = String(localized: "Privacy in NoteHush")
    window.contentMinSize = NSSize(width: 420, height: 320)
    window.tabbingMode = .disallowed
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
    window.delegate = self

    let scroll = NSScrollView(frame: NSRect(origin: .zero, size: window.contentLayoutRect.size))
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder

    let text = NSTextView(frame: scroll.contentView.bounds)
    text.identifier = NSUserInterfaceItemIdentifier("privacyText")
    text.isEditable = false
    text.isSelectable = true
    text.isRichText = false
    text.allowsUndo = false
    text.isHorizontallyResizable = false
    text.isVerticallyResizable = true
    text.autoresizingMask = [.width]
    text.minSize = .zero
    text.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    text.textContainerInset = NSSize(width: 28, height: 24)
    text.textContainer?.widthTracksTextView = true
    text.textContainer?.containerSize = NSSize(
      width: scroll.contentSize.width - 56, height: CGFloat.greatestFiniteMagnitude)
    text.backgroundColor = .textBackgroundColor
    text.setAccessibilityLabel(String(localized: "Privacy in NoteHush"))
    text.textStorage?.setAttributedString(Self.content())
    scroll.documentView = text
    window.contentView = scroll
    window.initialFirstResponder = text
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func windowWillClose(_ notification: Notification) {
    onClose()
  }

  private static func content() -> NSAttributedString {
    let result = NSMutableAttributedString()
    func append(_ value: String, size: CGFloat = 14, weight: NSFont.Weight = .regular) {
      let paragraph = NSMutableParagraphStyle()
      paragraph.paragraphSpacing = 14
      paragraph.lineSpacing = 3
      result.append(
        NSAttributedString(
          string: value + "\n",
          attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraph,
          ]))
    }

    append(String(localized: "Your text stays yours."), size: 24, weight: .semibold)
    append(
      String(
        localized:
          "NoteHush works locally on your Mac. The app does not send your notes, file contents, clipboard contents or usage activity to the developer. There are no accounts, advertisements, tracking or analytics SDKs."
      ))

    append(String(localized: "Files and recovery"), size: 16, weight: .semibold)
    append(
      String(
        localized:
          "NoteHush accesses files you select and keeps recovery copies in its private macOS sandbox. These copies include open drafts, unsaved edits, recently closed tabs, file references, preferences and your place in the workspace. Locally stored macOS bookmarks let NoteHush reopen files you previously selected."
      ))
    append(
      String(
        localized:
          "Closing the window or quitting keeps your workspace for the next launch. It does not save unsaved edits to the original files. Use Save or Save As to save a file explicitly."
      ))

    append(String(localized: "Retention and removal"), size: 16, weight: .semibold)
    append(
      String(
        localized:
          "NoteHush retains up to 20 recently closed tabs. File → Clear Recently Closed Tabs removes them from the reopen list. Open drafts, earlier recovery generations, preserved damaged data, saved files and system backups may still contain copies. Clearing this list is not secure erasure."
      ))
    append(
      String(
        localized:
          "Save any work you want to keep before removing local app data. Copies in saved files, synced folders and backups must be managed separately. The developer cannot access or remotely delete your local notes."
      ))

    append(String(localized: "Services you choose"), size: 16, weight: .semibold)
    append(
      String(
        localized:
          "Files you save may be synced or backed up by macOS or a storage provider you choose. Printing and PDF output use the system services and destination you select. NoteHush does not operate a cloud sync or backup service."
      ))
    append(
      String(
        localized:
          "NoteHush does not automatically upload notes, recovery folders, screenshots or application logs. Apple may separately process purchase, download or diagnostic information according to your Apple settings and its policies. If you contact support, you choose what to send; use invented example text whenever possible."
      ))
    return result
  }
}
