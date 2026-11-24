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
  private let paragraphPresenter = ParagraphDirectionPresenter()
  let editor: NSTextView
  let scrollView: NSScrollView
  var onChange: (() -> Void)?
  var onStatusChange: (() -> Void)?
  private let history = UndoManager()
  private var savedScroll: TextScrollPosition?
  private var restoring = false
  private var observingScroll = false
  private var preferences = EditorPreferences()
  private var capturedSnapshot: TabSnapshot
  private var textCaptureInvalidated = false
  private var contentNotificationPending = false

  var text: String { editor.string }
  var textSelection: NSRange { editor.selectedRange() }

  func selectText(_ range: NSRange, reveal: Bool = false) {
    let clamped = TextSelection(location: range.location, length: range.length)
      .clamped(toUTF16Length: editor.textStorage?.length ?? 0)
    let nativeRange = NSRange(location: clamped.location, length: clamped.length)
    editor.setSelectedRange(nativeRange)
    if reveal { editor.scrollRangeToVisible(nativeRange) }
  }

  init(
    snapshot: TabSnapshot, preferences: EditorPreferences = EditorPreferences(),
    scrollerStyle: NSScroller.Style? = nil,
    analyzer: any TextAnalyzing = BackgroundTextAnalyzer()
  ) {
    id = snapshot.id
    title = snapshot.title
    file = snapshot.file
    self.analyzer = analyzer
    metrics = snapshot.text.isEmpty ? .empty : nil
    isDirty = !snapshot.text.isEmpty
    savedScroll = snapshot.scroll
    capturedSnapshot = snapshot
    let initialFrame = NSRect(x: 0, y: 0, width: 900, height: 500)
    editor = NSTextView(usingTextLayoutManager: true)
    editor.frame = initialFrame
    guard let storage = editor.textStorage, let container = editor.textContainer,
      editor.textLayoutManager != nil
    else {
      preconditionFailure("Native TextKit 2 editor construction failed")
    }
    scrollView = NSScrollView(frame: initialFrame)
    super.init()
    if let content = editor.textLayoutManager?.textContentManager as? NSTextContentStorage,
      content.delegate == nil
    {
      content.delegate = paragraphPresenter
    }
    if let scrollerStyle { scrollView.scrollerStyle = scrollerStyle }
    editor.isRichText = false
    editor.importsGraphics = false
    editor.allowsUndo = true
    editor.usesFindBar = true
    editor.isIncrementalSearchingEnabled = true
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.isAutomaticTextReplacementEnabled = false
    editor.isAutomaticSpellingCorrectionEnabled = false
    editor.inlinePredictionType = .no
    editor.isAutomaticTextCompletionEnabled = false
    if #available(macOS 15.0, *) {
      editor.mathExpressionCompletionType = .no
      editor.writingToolsBehavior = .none
    }
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
    scrollView.hasVerticalScroller = true
    // Legacy scrollbar auto-hiding can lay out the first paragraph when text
    // is assigned. Enable it during presentation, after hidden restoration.
    scrollView.autohidesScrollers = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    // Attaching a populated NSTextView invalidates its content style and can
    // force expensive bidirectional layout before any tab is shown.
    scrollView.documentView = editor
    applyPreferences(preferences)
    editor.string = snapshot.text
    let selection = snapshot.selection.clamped(toUTF16Length: storage.length)
    editor.setSelectedRange(NSRange(location: selection.location, length: selection.length))
    editor.delegate = self
    NotificationCenter.default.addObserver(
      self, selector: #selector(storageDidProcessEditing),
      name: NSTextStorage.didProcessEditingNotification, object: storage)
    // TextKit 2 updates storage during Undo/Redo without consistently sending
    // NSTextView's text-change notification. Reconcile only an observed pending
    // character edit when the tab's own undo transaction finishes.
    for name in [
      NSNotification.Name.NSUndoManagerDidUndoChange,
      NSNotification.Name.NSUndoManagerDidRedoChange,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(historyDidChange), name: name, object: history)
    }
    scrollView.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(
      self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
      object: scrollView.contentView)
    refreshDirtyState()
  }

  isolated deinit {
    NotificationCenter.default.removeObserver(self)
    editor.delegate = nil
    // Removing the document view can ask TextKit for viewport geometry. Keep
    // the paragraph delegate alive during that work; releasing the scroll view
    // later must not fall back to document-wide direction inference.
    withExtendedLifetime(paragraphPresenter) {
      scrollView.documentView = nil
    }
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
  @objc private func storageDidProcessEditing(_ notification: Notification) {
    guard let storage = notification.object as? NSTextStorage,
      storage.editedMask.contains(.editedCharacters)
    else { return }
    // Covers direct storage changes, undo and input-method edits as well as
    // NSTextView delegate callbacks. Presentation-only changes keep the text identity.
    textCaptureInvalidated = true
    contentNotificationPending = true
  }

  @objc private func historyDidChange(_ notification: Notification) {
    if contentNotificationPending { textDidChange(notification) }
  }

  func textDidChange(_ notification: Notification) {
    guard contentNotificationPending else { return }
    contentNotificationPending = false
    contentRevision &+= 1
    isDirty = file != nil || !text.isEmpty
    refreshDirtyState()
    metrics = text.isEmpty ? .empty : nil
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
        let textSnapshot = text
        let result = try await analyzer.analyze(textSnapshot)
        try Task.checkCancellation()
        guard statusActive, revision == contentRevision else { return }
        metrics = result
        onStatusChange?()
      } catch {}
    }
  }

  func snapshot(isVisible: Bool) -> TabSnapshot {
    if isVisible && observingScroll { captureScroll() }
    let range = textSelection
    // A caller can capture inside beginEditing/endEditing before the storage
    // notification is delivered. Its pending character mask must invalidate too.
    if textCaptureInvalidated || editor.textStorage?.editedMask.contains(.editedCharacters) == true
    {
      capturedSnapshot.text = text
      textCaptureInvalidated = false
    }
    capturedSnapshot.title = title
    capturedSnapshot.selection = TextSelection(location: range.location, length: range.length)
      .clamped(toUTF16Length: editor.textStorage?.length ?? 0)
    capturedSnapshot.scroll = savedScroll
    capturedSnapshot.file = file
    return capturedSnapshot
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
      opened.text, replacementRange: NSRange(location: 0, length: text.utf16.count))
    history.setActionName(String(localized: "Reload File"))
    history.endUndoGrouping()
    editor.breakUndoCoalescing()
    bind(opened.binding, grantedURL: grantedURL)
  }

  func waitForDirtyState() async { await dirtyCheck?.value }

  private func refreshDirtyState(immediate: Bool = false) {
    dirtyCheck?.cancel()
    guard let file else {
      isDirty = !text.isEmpty
      return
    }
    let text = self.text
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
    scrollView.autohidesScrollers = true
    editor.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
    configureWrapping()
    guard let layout = editor.textLayoutManager, let content = layout.textContentManager,
      !text.isEmpty
    else {
      editor.setFrameOrigin(.zero)
      scrollView.contentView.scroll(to: .zero)
      return
    }
    let position =
      savedScroll.flatMap { $0.offset.isFinite ? $0 : nil }
      ?? TextScrollPosition(anchor: 0, offset: -editor.textContainerInset.height)
    let anchor = min(max(position.anchor, 0), text.utf16.count - 1)
    // Native scrolling lays out the anchor's visible area and updates its
    // estimated geometry before we apply the saved offset. A single-character
    // layout request can leave that offset pointing at a different line.
    editor.scrollRangeToVisible(NSRange(location: anchor, length: 1))
    editor.sizeToFit()
    layout.textViewportLayoutController.layoutViewport()
    guard let location = content.location(content.documentRange.location, offsetBy: anchor),
      let end = content.location(location, offsetBy: 1),
      let range = NSTextRange(location: location, end: end)
    else { return }
    layout.ensureLayout(for: range)
    guard let fragment = layout.textLayoutFragment(for: location),
      let line = fragment.textLineFragment(for: location, isUpstreamAffinity: false)
    else { return }
    // NSText sizes about its previous top edge while detached. The scroll
    // document must start at zero before clip-view constraints are applied.
    editor.setFrameOrigin(.zero)
    let y =
      fragment.layoutFragmentFrame.minY + line.typographicBounds.minY
      + editor.textContainerOrigin.y + max(-1000, min(position.offset, 1000))
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
    guard !restoring, let layout = editor.textLayoutManager,
      let content = layout.textContentManager,
      let length = editor.textStorage?.length, length > 0
    else { return }
    let y = scrollView.contentView.bounds.minY
    let point = NSPoint(x: 0, y: max(0, y - editor.textContainerOrigin.y))
    guard let fragment = layout.textLayoutFragment(for: point),
      let line = fragment.textLineFragment(
        forVerticalOffset: point.y - fragment.layoutFragmentFrame.minY, requiresExactMatch: false)
    else { return }
    let elementOffset = content.offset(
      from: content.documentRange.location, to: fragment.rangeInElement.location)
    guard elementOffset != NSNotFound, elementOffset >= 0, elementOffset <= length,
      line.characterRange.location <= length - elementOffset
    else { return }
    let anchor = min(length - 1, elementOffset + line.characterRange.location)
    savedScroll = TextScrollPosition(
      anchor: anchor,
      offset: y - fragment.layoutFragmentFrame.minY - line.typographicBounds.minY
        - editor.textContainerOrigin.y,
      horizontalOffset: scrollView.contentView.bounds.minX)
  }
}
