import AppKit
import NoteHushCore

@MainActor
final class EditorTab: NSObject, NSTextViewDelegate {
  let id: UUID
  private(set) var title: String
  private(set) var file: FileBinding?
  private(set) var isDirty: Bool
  // In-memory panel/Finder authority. Recovered paths alone grant no access.
  private(set) var grantedURL: URL?
  private var dirtyCheck: Task<Void, Never>?
  private var contentRevision: UInt64 = 0
  let editor: NSTextView
  let scrollView = NSScrollView()
  var onChange: (() -> Void)?
  private let history = UndoManager()
  private var savedScroll: TextScrollPosition?
  private var restoring = false
  private var observingScroll = false

  init(snapshot: TabSnapshot) {
    id = snapshot.id
    title = snapshot.title
    file = snapshot.file
    isDirty = !snapshot.text.isEmpty
    savedScroll = snapshot.scroll
    let storage = NSTextStorage()
    let layout = NSLayoutManager()
    let container = NSTextContainer(
      containerSize: NSSize(width: 900, height: CGFloat.greatestFiniteMagnitude))
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    editor = NSTextView(
      frame: NSRect(x: 0, y: 0, width: 900, height: 500), textContainer: container)
    super.init()
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
    container.widthTracksTextView = true
    editor.setAccessibilityLabel(String(localized: "Note text"))
    editor.setAccessibilityIdentifier("note-editor")
    editor.string = snapshot.text
    let selection = snapshot.selection.clamped(toUTF16Length: editor.string.utf16.count)
    editor.setSelectedRange(NSRange(location: selection.location, length: selection.length))
    editor.delegate = self
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = editor
    scrollView.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(
      self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
      object: scrollView.contentView)
    refreshDirtyState()
  }

  func undoManager(for view: NSTextView) -> UndoManager? { history }
  func textDidChange(_ notification: Notification) {
    contentRevision &+= 1
    isDirty = file != nil || !editor.string.isEmpty
    refreshDirtyState()
    onChange?()
  }
  func textViewDidChangeSelection(_ notification: Notification) { onChange?() }

  func snapshot(isVisible: Bool) -> TabSnapshot {
    if isVisible && observingScroll { captureScroll() }
    let range = editor.selectedRange()
    return TabSnapshot(
      id: id, title: title, text: editor.string,
      selection: TextSelection(location: range.location, length: range.length)
        .clamped(toUTF16Length: editor.string.utf16.count), scroll: savedScroll, file: file)
  }

  func bind(_ binding: FileBinding, grantedURL: URL) {
    self.file = binding
    self.grantedURL = grantedURL
    title = binding.url.lastPathComponent
    // This comparison runs after disk I/O, so typing during a save stays dirty.
    refreshDirtyState(immediate: true)
    onChange?()
  }

  func grantAccess(to url: URL) { grantedURL = url }

  func waitForDirtyState() async { await dirtyCheck?.value }

  private func refreshDirtyState(immediate: Bool = false) {
    dirtyCheck?.cancel()
    guard let file else {
      isDirty = !editor.string.isEmpty
      return
    }
    let text = editor.string
    let revision = contentRevision
    dirtyCheck = Task { [weak self] in
      do {
        if !immediate { try await Task.sleep(for: .milliseconds(250)) }
        let digest = await Task.detached(priority: .utility) { TextDocumentCodec.textDigest(text) }
          .value
        try Task.checkCancellation()
        guard let self, contentRevision == revision else { return }
        isDirty = digest != file.textDigest
        onChange?()
      } catch {}
    }
  }

  func restoreScroll() {
    restoring = true
    defer {
      restoring = false
      observingScroll = true
    }
    editor.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
    guard let layout = editor.layoutManager, let container = editor.textContainer,
      !editor.string.isEmpty
    else {
      editor.setFrameOrigin(.zero)
      scrollView.contentView.scroll(to: .zero)
      return
    }
    let position =
      savedScroll.flatMap { $0.offset.isFinite ? $0 : nil }
      ?? TextScrollPosition(anchor: 0, offset: -editor.textContainerInset.height)
    let anchor = min(max(position.anchor, 0), editor.string.utf16.count - 1)
    layout.ensureLayout(forCharacterRange: NSRange(location: 0, length: anchor + 1))
    let glyph = layout.glyphIndexForCharacter(at: anchor)
    let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    layout.ensureLayout(for: container)
    editor.sizeToFit()
    // NSText sizes about its previous top edge while detached. The scroll
    // document must start at zero before clip-view constraints are applied.
    editor.setFrameOrigin(.zero)
    let y = line.minY + editor.textContainerInset.height + max(-1000, min(position.offset, 1000))
    let clip = scrollView.contentView
    let proposed = NSRect(origin: NSPoint(x: 0, y: max(0, y)), size: clip.bounds.size)
    clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
    scrollView.reflectScrolledClipView(clip)
  }

  func suspendScrollObservation() { observingScroll = false }

  @objc private func scrolled() {
    guard observingScroll, !restoring, scrollView.window != nil else { return }
    captureScroll()
    onChange?()
  }

  private func captureScroll() {
    guard !restoring, let layout = editor.layoutManager, let container = editor.textContainer,
      layout.numberOfGlyphs > 0
    else { return }
    let y = scrollView.contentView.bounds.minY
    let point = NSPoint(x: 0, y: max(0, y - editor.textContainerInset.height))
    let glyph = min(layout.glyphIndex(for: point, in: container), layout.numberOfGlyphs - 1)
    let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    savedScroll = TextScrollPosition(
      anchor: layout.characterIndexForGlyph(at: glyph),
      offset: y - line.minY - editor.textContainerInset.height)
  }
}
