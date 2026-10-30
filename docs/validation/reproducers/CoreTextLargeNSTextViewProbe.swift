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

@MainActor func nativePlan(_ source: NSAttributedString, width: CGFloat, direction: NSWritingDirection) -> [LineSpan] {
  let mutable = NSMutableAttributedString(attributedString: source)
  let style = (source.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
  style.baseWritingDirection = direction
  mutable.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: mutable.length))
  let content = NSTextContentStorage(); let storage = NSTextStorage(attributedString: mutable); content.textStorage = storage
  let manager = NSTextLayoutManager(); content.addTextLayoutManager(manager); content.primaryTextLayoutManager = manager
  manager.textContainer = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)); manager.ensureLayout(for: manager.documentRange)
  var spans: [LineSpan] = []
  _ = manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: []) { fragment in
    guard let range = fragment.textElement?.elementRange else { return false }
    let base = content.offset(from: content.documentRange.location, to: range.location)
    for line in fragment.textLineFragments { spans.append(LineSpan(start: base + line.characterRange.location, length: line.characterRange.length)) }
    return true
  }
  return spans
}

@MainActor func incrementalSpans(_ original: [LineSpan], edited: NSAttributedString, position: Int, width: CGFloat, window: Int, direction: NSWritingDirection) -> (spans: [LineSpan], windows: Int, convergence: Int) {
  let delta = edited.length - (original.last.map { $0.start + $0.length } ?? 0)
  let startIndex = max(0, original.lastIndex(where: { $0.start <= position }) ?? 0)
  let prefix = Array(original.prefix(startIndex))
  let oldByStart = Dictionary(uniqueKeysWithValues: original.enumerated().map { ($0.element.start, $0.offset) })
  var cursor = original[startIndex].start
  var localAll: [LineSpan] = []
  var windows = 0
  while cursor < edited.length {
    let n = min(window, edited.length - cursor)
    let part = edited.attributedSubstring(from: NSRange(location: cursor, length: n))
    var local = nativePlan(part, width: width, direction: direction).map { LineSpan(start: cursor + $0.start, length: $0.length) }
    if cursor + n < edited.length && local.count > 1 { local.removeLast() }
    guard let last = local.last else { break }
    localAll.append(contentsOf: local); windows += 1
    if localAll.count >= 2 {
      let firstCandidate = max(0, localAll.count - 6)
      for j in firstCandidate..<(localAll.count - 1) {
        let a = localAll[j], b = localAll[j + 1]
        guard a.start >= position + delta,
          let oldA = oldByStart[a.start - delta], oldA + 1 < original.count else { continue }
        if original[oldA].length == a.length,
          original[oldA + 1].start + delta == b.start,
          original[oldA + 1].length == b.length {
          let rebuilt = prefix + Array(localAll.prefix(j + 2)) + original.dropFirst(oldA + 2).map { LineSpan(start: $0.start + delta, length: $0.length) }
          return (rebuilt, windows, localAll[j].start)
        }
      }
    }
    cursor = last.start + last.length
  }
  return (prefix + localAll, windows, 0)
}



@MainActor func groupedSpans(_ lines: [LineSpan], maximumLength: Int) -> [LineSpan] {
  guard let first = lines.first else { return [] }
  var result: [LineSpan] = []
  var start = first.start
  var end = first.start + first.length
  for line in lines.dropFirst() {
    let lineEnd = line.start + line.length
    if lineEnd - start > maximumLength {
      result.append(LineSpan(start: start, length: end - start))
      start = line.start
    }
    end = lineEnd
  }
  result.append(LineSpan(start: start, length: end - start))
  return result
}


@MainActor func largeTarget(_ target: String) throws {
  let header = "123456789012345\n"
  let unit = "خط📝"
  let bytes = 10_485_760
  let text = header + String(repeating: unit, count: (bytes - header.utf8.count) / unit.utf8.count)
  let style = NSMutableParagraphStyle(); style.baseWritingDirection = .natural
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let source = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
  guard source.string.utf8.count == bytes else { throw NSError(domain: "probe", code: 9) }
  let planStart = ContinuousClock.now
  let spans = plannedSpans(source, width: 858, cap: 65536)
  let planElapsed = planStart.duration(to: .now)
  let backing = NSTextStorage(attributedString: source)
  let customContent = PlannedContentStorage(); customContent.textStorage = backing; customContent.setSpans(groupedSpans(spans, maximumLength: 2048))
  let customManager = NSTextLayoutManager(); customContent.addTextLayoutManager(customManager); customContent.primaryTextLayoutManager = customManager
  let customContainer = NSTextContainer(size: NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude)); customManager.textContainer = customContainer
  let editor = NSTextView(frame: NSRect(x:0,y:0,width:900,height:500), textContainer: customContainer); editor.textContainerInset = NSSize(width:16,height:16); editor.isRichText = false
  let window = NSWindow(contentRect: editor.frame, styleMask: .borderless, backing: .buffered, defer: false); window.contentView = editor
  let total = backing.length
  editor.allowsUndo = true
  editor.font = font
  editor.typingAttributes = [.font: font, .paragraphStyle: style]
  _ = window.makeFirstResponder(editor)
  let before = editor.string
  let insertion = total / 2
  editor.setSelectedRange(NSRange(location: insertion, length: 0))
  let editStarted = ContinuousClock.now
  editor.insertText("X", replacementRange: NSRange(location: insertion, length: 0))
  let editElapsed = editStarted.duration(to: .now)
  let edited = editor.string
  var editedUnits = Array(edited.utf16)
  let insertedAt = (edited as NSString).range(of: "X").location
  let editExact: Bool
  if insertedAt == insertion && insertedAt < editedUnits.count && editedUnits[insertedAt] == 88 {
    editedUnits.remove(at: insertedAt)
    editExact = editedUnits.elementsEqual(before.utf16)
  } else { editExact = false }
  let editedSource = NSAttributedString(string: edited, attributes: [.font: font, .paragraphStyle: style])
  let reflowStarted = ContinuousClock.now
  let reflow = incrementalSpans(
    spans, edited: editedSource, position: insertion, width: 868, window: 2048,
    direction: .rightToLeft)
  let reflowElapsed = reflowStarted.duration(to: .now)
  let replacementStarted = ContinuousClock.now
  let replannedContent = PlannedContentStorage()
  replannedContent.textStorage = backing
  replannedContent.setSpans(groupedSpans(reflow.spans, maximumLength: 2048))
  customManager.replace(replannedContent)
  customManager.invalidateLayout(for: customManager.documentRange)
  let replacementElapsed = replacementStarted.duration(to: .now)
  let editRangeStart = replannedContent.location(replannedContent.documentRange.location, offsetBy: insertion)
  let editRangeEnd = replannedContent.location(replannedContent.documentRange.location, offsetBy: insertion + 512)
  var editedLayoutCovered = false
  let ensureEditStarted = ContinuousClock.now
  if let editRangeStart, let editRangeEnd, let editRange = NSTextRange(location: editRangeStart, end: editRangeEnd) {
    customManager.ensureLayout(for: editRange)
    editedLayoutCovered = true
  }
  let ensureEditElapsed = ensureEditStarted.duration(to: .now)
  print("editAtMiddle=\(insertion) editMs=\(editElapsed) reflow=\(reflowElapsed) replace=\(replacementElapsed) ensureEdit=\(ensureEditElapsed) editCaret=\(editor.selectedRange().location) editExact=\(editExact) reflowWindows=\(reflow.windows) convergence=\(reflow.convergence) editedLayoutCovered=\(editedLayoutCovered) managerReplaced=\(editor.textContentStorage === replannedContent)")
  for target in ["start", "middle", "end"] {
    let start: Int
    switch target { case "start": start = 16; case "middle": start = total / 2; default: start = max(0,total-128) }
    let length = min(1024,total-start)
    guard let a = replannedContent.location(replannedContent.documentRange.location, offsetBy:start),
          let b = replannedContent.location(replannedContent.documentRange.location, offsetBy:start+length),
          let range = NSTextRange(location:a,end:b) else { throw NSError(domain:"probe",code:10) }
    let requestStart = ContinuousClock.now
    customManager.ensureLayout(for: range)
    let ensureElapsed=requestStart.duration(to:.now)
    var lineRanges: [(Int,Int)] = []
    var covered=start
    _ = customManager.enumerateTextLayoutFragments(from:a, options:[.ensuresLayout]) { f in
      guard let loc=f.textElement?.elementRange?.location else { return false }
      let base=replannedContent.offset(from:replannedContent.documentRange.location,to:loc)
      for line in f.textLineFragments {
        let lineStart=base+line.characterRange.location
        lineRanges.append((lineStart,line.characterRange.length))
        if lineStart <= covered && lineStart + line.characterRange.length > covered { covered=lineStart+line.characterRange.length }
      }
      return covered < start+length
    }
    print("target=\(target) sourceBytes=\(text.utf8.count) sourceUTF16=\(total) plannedSpans=\(spans.count) planSeconds=\(planElapsed) ensureSeconds=\(ensureElapsed) rows=\(lineRanges.count) coveredThrough=\(covered) targetCovered=\(covered>=start+length) attached=\(editor.textContentStorage === replannedContent)")
  }
  editor.undoManager?.undo()
  let undoExact = editor.string.utf16.elementsEqual(before.utf16)
  print("undoExact=\(undoExact) undoCaret=\(editor.selectedRange().location == insertion)")
  withExtendedLifetime(window) {}
}

@main @MainActor enum Main {
  static func main() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    try largeTarget("all")
  }
}
