@preconcurrency import AppKit
import CoreText
import Foundation
import os

@MainActor struct LineSpan { let start: Int; let length: Int }

@MainActor func plannedSpans(_ source: NSAttributedString, width: Double, cap: Int) -> [LineSpan] {
  var spans: [LineSpan] = []
  var start = 0
  while start < source.length {
    let length = min(cap, source.length - start)
    let candidate = source.attributedSubstring(from: NSRange(location: start, length: length))
    let typesetter = CTTypesetterCreateWithAttributedString(candidate as CFAttributedString)
    var local: [LineSpan] = []
    var offset = 0
    while offset < candidate.length {
      let count = CTTypesetterSuggestLineBreak(typesetter, offset, width)
      guard count > 0 else { break }
      local.append(LineSpan(start: start + offset, length: count))
      offset += count
    }
    if start + length < source.length && local.count > 1 {
      spans.append(contentsOf: local.dropLast())
      start = local[local.count - 2].start + local[local.count - 2].length
    } else {
      spans.append(contentsOf: local)
      start += length
    }
  }
  return spans
}

@MainActor final class PlannedContentStorage: NSTextContentStorage {
  nonisolated private let spansLock = OSAllocatedUnfairLock(initialState: [LineSpan]())
  nonisolated private let locationsLock = OSAllocatedUnfairLock(initialState: [ObjectIdentifier: Int]())
  nonisolated private let emittedLock = OSAllocatedUnfairLock(initialState: 0)
  var emitted: Int { emittedLock.withLock { $0 } }
  func setSpans(_ spans: [LineSpan]) { spansLock.withLock { $0 = spans } }
  nonisolated private func remember(_ location: any NSTextLocation, _ offset: Int) {
    locationsLock.withLock { $0[ObjectIdentifier(location as AnyObject)] = offset }
  }
  nonisolated private func knownOffset(_ location: any NSTextLocation) -> Int? {
    locationsLock.withLock { $0[ObjectIdentifier(location as AnyObject)] }
  }
  nonisolated override func enumerateTextElements(
    from textLocation: (any NSTextLocation)?,
    options: NSTextContentManager.EnumerationOptions,
    using block: (NSTextElement) -> Bool
  ) -> (any NSTextLocation)? {
    guard let storage = textStorage else { return nil }
    let range = documentRange
    let base = range.location
    let total = super.offset(from: base, to: range.endLocation)
    remember(base, 0); remember(range.endLocation, total)
    let requested = textLocation.flatMap { knownOffset($0) } ?? (options.contains(.reverse) ? total : 0)
    let spans = spansLock.withLock { $0 }
    guard total >= 0, requested >= 0, !spans.isEmpty else { return nil }
    let firstIndex = spans.lastIndex(where: { $0.start <= requested }) ?? 0
    let ordered = options.contains(.reverse) ? Array(spans.prefix(firstIndex + 1).reversed()) : Array(spans.dropFirst(firstIndex))
    for span in ordered {
      let start = max(0, min(total, span.start))
      let end = max(start, min(total, span.start + span.length))
      guard end > start,
            let startLocation = super.location(base, offsetBy: start),
            let endLocation = super.location(base, offsetBy: end),
            let elementRange = NSTextRange(location: startLocation, end: endLocation) else { return nil }
      remember(startLocation, start); remember(endLocation, end)
      let paragraph = NSTextParagraph(attributedString: storage.attributedSubstring(from: NSRange(location: start, length: end - start)))
      paragraph.textContentManager = self
      paragraph.elementRange = elementRange
      emittedLock.withLock { $0 += 1 }
      if !block(paragraph) { return options.contains(.reverse) ? startLocation : endLocation }
    }
    return options.contains(.reverse) ? super.location(base, offsetBy: 0) : super.location(base, offsetBy: total)
  }
  nonisolated override func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (any NSTextLocation)? {
    let base = knownOffset(location) ?? super.offset(from: documentRange.location, to: location)
    guard base != NSNotFound, let value = super.location(location, offsetBy: offset) else { return nil }
    remember(value, base + offset)
    return value
  }
  nonisolated override func offset(from start: any NSTextLocation, to end: any NSTextLocation) -> Int {
    guard let a = knownOffset(start), let b = knownOffset(end) else { return NSNotFound }
    return b - a
  }
}

@MainActor func geometry(_ manager: NSTextLayoutManager, content: NSTextContentStorage) -> [(Int,Int,UInt)] {
  var rows: [(Int,Int,UInt)] = []
  _ = manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { f in
    guard let location = f.textElement?.elementRange?.location else { return false }
    let start = content.offset(from: content.documentRange.location, to: location)
    for line in f.textLineFragments { rows.append((start + line.characterRange.location, line.characterRange.length, line.typographicBounds.width.bitPattern)) }
    return true
  }
  return rows
}

@MainActor func fixture(_ name: String, _ text: String) throws {
  let style = NSMutableParagraphStyle(); style.baseWritingDirection = .natural
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let source = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
  let spans = plannedSpans(source, width: 858, cap: 4096)

  let standardContent = NSTextContentStorage(); let standardStorage = NSTextStorage(attributedString: source); standardContent.textStorage = standardStorage
  let standardManager = NSTextLayoutManager(); standardContent.addTextLayoutManager(standardManager); standardContent.primaryTextLayoutManager = standardManager
  let standardContainer = NSTextContainer(size: NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude)); standardManager.textContainer = standardContainer
  standardManager.ensureLayout(for: standardManager.documentRange)
  let native = geometry(standardManager, content: standardContent)

  let backing = NSTextStorage(attributedString: source)
  let customContent = PlannedContentStorage(); customContent.textStorage = backing; customContent.setSpans(spans)
  let customManager = NSTextLayoutManager(); customContent.addTextLayoutManager(customManager); customContent.primaryTextLayoutManager = customManager
  let customContainer = NSTextContainer(size: NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude)); customManager.textContainer = customContainer
  let editor = NSTextView(frame: NSRect(x:0,y:0,width:900,height:500), textContainer: customContainer); editor.textContainerInset = NSSize(width:16,height:16); editor.isRichText = false
  let window = NSWindow(contentRect: editor.frame, styleMask: .borderless, backing: .buffered, defer: false); window.contentView = editor
  guard editor.textContentStorage === customContent else { fputs("custom-chain-not-attached\n", stderr); return }
  customManager.ensureLayout(for: customManager.documentRange)
  let observed = geometry(customManager, content: customContent)
  let exact = native.count == observed.count && zip(native, observed).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
  editor.allowsUndo = true
  _ = window.makeFirstResponder(editor)
  let before = editor.string
  let insertion = min(200, before.utf16.count - 1)
  editor.setSelectedRange(NSRange(location: insertion, length: 0))
  editor.insertText("X", replacementRange: NSRange(location: insertion, length: 0))
  let after = editor.string
  let selectionAfterEdit = editor.selectedRange()
  let insertedAt = (after as NSString).range(of: "X").location
  var unitsWithoutX = Array(after.utf16)
  let editExact: Bool
  if insertedAt == insertion && insertedAt < unitsWithoutX.count && unitsWithoutX[insertedAt] == 88 {
    unitsWithoutX.remove(at: insertedAt)
    editExact = unitsWithoutX.elementsEqual(before.utf16)
  } else { editExact = false }
  let rangeStart = customContent.location(customContent.documentRange.location, offsetBy: insertion)
  let rangeEnd = customContent.location(customContent.documentRange.location, offsetBy: min(after.utf16.count, insertion + 128))
  var relayoutSucceeded = false
  if let rangeStart, let rangeEnd, let range = NSTextRange(location: rangeStart, end: rangeEnd) {
    customManager.ensureLayout(for: range)
    relayoutSucceeded = true
  }
  let editedSource = NSAttributedString(string: after, attributes: [.font: font, .paragraphStyle: style])
  let replannedContent = PlannedContentStorage()
  replannedContent.textStorage = customContent.textStorage
  replannedContent.setSpans(plannedSpans(editedSource, width: 858, cap: 4096))
  customManager.replace(replannedContent)
  customManager.invalidateLayout(for: customManager.documentRange)
  customManager.ensureLayout(for: customManager.documentRange)
  let editedRows = geometry(customManager, content: replannedContent)
  let selectionPreserved = NSEqualRanges(editor.selectedRange(), selectionAfterEdit)
  let editedNativeContent = NSTextContentStorage(); let editedNativeStorage = NSTextStorage(attributedString: editedSource); editedNativeContent.textStorage = editedNativeStorage
  let editedNativeManager = NSTextLayoutManager(); editedNativeContent.addTextLayoutManager(editedNativeManager); editedNativeContent.primaryTextLayoutManager = editedNativeManager
  let editedNativeContainer = NSTextContainer(size: NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude)); editedNativeManager.textContainer = editedNativeContainer
  editedNativeManager.ensureLayout(for: editedNativeManager.documentRange)
  let editedNativeRows = geometry(editedNativeManager, content: editedNativeContent)
  let editGeometryExact = editedRows.count == editedNativeRows.count && zip(editedRows, editedNativeRows).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
  let replacementAttached = editor.textContentStorage === replannedContent
  editor.undoManager?.undo()
  let undoExact = editor.string.utf16.elementsEqual(before.utf16)
  let undoCaretRestored = editor.selectedRange().location == insertion && editor.selectedRange().length == 0
  print("name=\(name) units=\(source.length) plannedSpans=\(spans.count) nativeRows=\(native.count) customRows=\(observed.count) geometryExact=\(exact) editExact=\(editExact) relayoutSucceeded=\(relayoutSucceeded) editGeometryExact=\(editGeometryExact) replacementAttached=\(replacementAttached) selectionPreserved=\(selectionPreserved) editedNativeRows=\(editedNativeRows.count) editedCustomRows=\(editedRows.count) undoExact=\(undoExact) undoCaretRestored=\(undoCaretRestored) managerAttached=\(editor.textContentStorage === customContent)")
}

@main @MainActor enum Main {
  static func main() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    try fixture("rtl-emoji", String(repeating: "خط📝", count: 2000))
    try fixture("mixed-latin-numbers", String(repeating: "abc اردو 123 — שלום🙂 ", count: 500))
    try fixture("combining-rtl", String(repeating: "e\u{301} العربية العربية אבג 🧑🏽‍💻 ", count: 500))
    try fixture("punctuation-parens", String(repeating: "(rtl: العربية 42) [עברית, 7] — 🙂 ", count: 500))
  }
}
