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
  private let analyzer: any TextAnalyzing
  private var analysisTask: Task<Void, Never>?
  private var statusActive = false
  private(set) var metrics: TextMetrics?
  let editor: NSTextView
  let scrollView = NSScrollView()
  var onChange: (() -> Void)?
  var onStatusChange: (() -> Void)?
  private let history = UndoManager()
  private var savedScroll: TextScrollPosition?
  private var restoring = false
  private var observingScroll = false
  private var preferences = EditorPreferences()

  init(
    snapshot: TabSnapshot, preferences: EditorPreferences = EditorPreferences(),
    analyzer: any TextAnalyzing = BackgroundTextAnalyzer()
  ) {
    id = snapshot.id
    title = snapshot.title
    file = snapshot.file
    self.analyzer = analyzer
    metrics = snapshot.text.isEmpty ? .empty : nil
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
    editor.usesFindBar = true
    editor.isIncrementalSearchingEnabled = true
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
    applyPreferences(preferences)
    refreshDirtyState()
  }

  func applyPreferences(_ value: EditorPreferences) {
    let next = value.normalized
    let relayout =
      preferences.fontName != next.fontName || preferences.fontSize != next.fontSize
      || preferences.zoomPercent != next.zoomPercent || preferences.wordWrap != next.wordWrap
    let visible = observingScroll && scrollView.window != nil
    if relayout && visible { captureScroll() }
    restoring = true
    defer { restoring = false }
    preferences = next
    // Set presentation attributes directly, never insert attributed text or change selection.
    // This also leaves an in-progress input-method composition and undo grouping intact.
    if editor.font != next.font() { editor.font = next.font() }
    editor.isContinuousSpellCheckingEnabled = next.checksSpelling
    editor.isGrammarCheckingEnabled = false
    editor.isAutomaticSpellingCorrectionEnabled = false
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.isAutomaticTextReplacementEnabled = false
    if relayout { configureWrapping() }
    if relayout && visible { restoreScroll() }
  }

  private func configureWrapping() {
    let wrap = preferences.wordWrap
    scrollView.hasHorizontalScroller = !wrap
    editor.isHorizontallyResizable = !wrap
    editor.autoresizingMask = wrap ? [.width] : []
    editor.textContainer?.widthTracksTextView = wrap
    let width = max(1, scrollView.contentSize.width)
    editor.setFrameSize(NSSize(width: width, height: editor.frame.height))
    editor.textContainer?.containerSize = NSSize(
      width: wrap ? max(1, width - 2 * editor.textContainerInset.width) : .greatestFiniteMagnitude,
      height: .greatestFiniteMagnitude)
  }

  func undoManager(for view: NSTextView) -> UndoManager? { history }
  func textDidChange(_ notification: Notification) {
    contentRevision &+= 1
    isDirty = file != nil || !editor.string.isEmpty
    refreshDirtyState()
    metrics = editor.string.isEmpty ? .empty : nil
    if statusActive { scheduleAnalysis() }
    onStatusChange?()
    onChange?()
  }
  func textViewDidChangeSelection(_ notification: Notification) {
    onStatusChange?()
    onChange?()
  }

  func activateStatus() {
    statusActive = true
    if metrics == nil { scheduleAnalysis(immediate: true) }
    onStatusChange?()
  }

  func deactivateStatus() {
    statusActive = false
    analysisTask?.cancel()
  }

  func prepareForClose() {
    suspendScrollObservation()
    deactivateStatus()
    dirtyCheck?.cancel()
    onChange = nil
    onStatusChange = nil
    editor.breakUndoCoalescing()
  }

  func waitForAnalysis() async { await analysisTask?.value }

  private func scheduleAnalysis(immediate: Bool = false) {
    analysisTask?.cancel()
    guard metrics == nil else { return }
    analysisTask = Task { [weak self] in
      do {
        if !immediate { try await Task.sleep(for: .milliseconds(250)) }
        try Task.checkCancellation()
        guard let self, statusActive else { return }
        // Take the immutable text snapshot only after the typing debounce.
        let revision = contentRevision
        let text = editor.string
        let result = try await analyzer.analyze(text)
        try Task.checkCancellation()
        guard statusActive, revision == contentRevision else { return }
        metrics = result
        onStatusChange?()
      } catch {}
    }
  }

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
    onStatusChange?()
    onChange?()
  }

  func grantAccess(to url: URL) { grantedURL = url }

  func relocate(using binding: FileBinding, grantedURL: URL) {
    guard let file else { return }
    self.file = file.relocating(to: binding.url, bookmark: binding.bookmark)
    self.grantedURL = grantedURL
    title = binding.url.lastPathComponent
    onChange?()
  }

  /// Reload is deliberate and undoable. The external version becomes the new
  /// baseline; Undo restores the prior draft and correctly marks it unsaved.
  func reload(_ opened: OpenedTextFile, grantedURL: URL) {
    editor.breakUndoCoalescing()
    history.beginUndoGrouping()
    editor.insertText(
      opened.text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    history.setActionName(String(localized: "Reload File"))
    history.endUndoGrouping()
    editor.breakUndoCoalescing()
    bind(opened.binding, grantedURL: grantedURL)
  }

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
    configureWrapping()
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
    let horizontal = position.horizontalOffset ?? 0
    let x = !preferences.wordWrap && horizontal.isFinite ? max(0, horizontal) : 0
    let proposed = NSRect(origin: NSPoint(x: x, y: max(0, y)), size: clip.bounds.size)
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
      offset: y - line.minY - editor.textContainerInset.height,
      horizontalOffset: scrollView.contentView.bounds.minX)
  }
}
