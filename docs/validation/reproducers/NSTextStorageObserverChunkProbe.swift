@preconcurrency import AppKit
import CoreText
import Foundation
import os

struct LineSpan: Sendable {
  let start: Int
  let length: Int
}

func plannedSpans(_ source: NSAttributedString, width: Double, cap: Int) -> [LineSpan] {
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
  nonisolated private let locationsLock = OSAllocatedUnfairLock(
    initialState: [ObjectIdentifier: Int]())
  nonisolated private let emittedLock = OSAllocatedUnfairLock(initialState: 0)
  nonisolated private let wholeSuffixCoreTextReplanLock = OSAllocatedUnfairLock(
    initialState: false)
  var emitted: Int { emittedLock.withLock { $0 } }
  func setSpans(_ spans: [LineSpan]) { spansLock.withLock { $0 = spans } }
  func spansSnapshot() -> [LineSpan] { spansLock.withLock { $0 } }
  func setWholeSuffixCoreTextReplan(_ enabled: Bool) {
    wholeSuffixCoreTextReplanLock.withLock { $0 = enabled }
  }
  nonisolated override func processEditing(
    for textStorage: NSTextStorage,
    edited editMask: NSTextStorageEditActions,
    range newRange: NSRange,
    changeInLength delta: Int,
    invalidatedRange: NSRange
  ) {
    if editMask.contains(.editedCharacters) {
      let replanWholeSuffix = wholeSuffixCoreTextReplanLock.withLock { $0 }
      let old = spansLock.withLock { $0 }
      let oldEnd = newRange.location + newRange.length - delta
      let first = old.lastIndex(where: { $0.start <= newRange.location }) ?? 0
      let last = max(first, old.lastIndex(where: { $0.start < oldEnd }) ?? first)
      if first < old.count, last < old.count {
        let base = old[first].start
        let priorEnd = old[last].start + old[last].length
        let newEnd = replanWholeSuffix ? textStorage.length : priorEnd + delta
        let newLength = max(0, newEnd - base)
        let local = textStorage.attributedSubstring(
          from: NSRange(location: base, length: newLength))
        let replanned = groupedSpans(
          plannedSpans(local, width: 858, cap: 65_536), maximumLength: 2048
        )
        .map { LineSpan(start: base + $0.start, length: $0.length) }
        let oldRangeLength = priorEnd - base
        let appliedDelta =
          replanned.reduce(0) { $0 + $1.length }
          - (replanWholeSuffix ? newEnd - base : oldRangeLength)
        let suffix =
          replanWholeSuffix
          ? []
          : old.dropFirst(last + 1).map {
            LineSpan(start: $0.start + appliedDelta, length: $0.length)
          }
        let updated = Array(old.prefix(first)) + replanned + suffix
        spansLock.withLock { $0 = updated }
      }
    }
    super.processEditing(
      for: textStorage, edited: editMask, range: newRange, changeInLength: delta,
      invalidatedRange: invalidatedRange)
  }
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
    remember(base, 0)
    remember(range.endLocation, total)
    let requested =
      textLocation.flatMap { knownOffset($0) } ?? (options.contains(.reverse) ? total : 0)
    let spans = spansLock.withLock { $0 }
    guard total >= 0, requested >= 0, !spans.isEmpty else { return nil }
    let firstIndex = spans.lastIndex(where: { $0.start <= requested }) ?? 0
    let ordered =
      options.contains(.reverse)
      ? Array(spans.prefix(firstIndex + 1).reversed()) : Array(spans.dropFirst(firstIndex))
    for span in ordered {
      let start = max(0, min(total, span.start))
      let end = max(start, min(total, span.start + span.length))
      guard end > start,
        let startLocation = super.location(base, offsetBy: start),
        let endLocation = super.location(base, offsetBy: end),
        let elementRange = NSTextRange(location: startLocation, end: endLocation)
      else { return nil }
      remember(startLocation, start)
      remember(endLocation, end)
      let paragraph = NSTextParagraph(
        attributedString: storage.attributedSubstring(
          from: NSRange(location: start, length: end - start)))
      paragraph.textContentManager = self
      paragraph.elementRange = elementRange
      emittedLock.withLock { $0 += 1 }
      if !block(paragraph) { return options.contains(.reverse) ? startLocation : endLocation }
    }
    return options.contains(.reverse)
      ? super.location(base, offsetBy: 0) : super.location(base, offsetBy: total)
  }
  nonisolated override func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (
    any NSTextLocation
  )? {
    let base = knownOffset(location) ?? super.offset(from: documentRange.location, to: location)
    guard base != NSNotFound, let value = super.location(location, offsetBy: offset) else {
      return nil
    }
    remember(value, base + offset)
    return value
  }
  nonisolated override func offset(from start: any NSTextLocation, to end: any NSTextLocation)
    -> Int
  {
    guard let a = knownOffset(start), let b = knownOffset(end) else { return NSNotFound }
    return b - a
  }
}

@MainActor func geometry(_ manager: NSTextLayoutManager, content: NSTextContentStorage) -> [(
  Int, Int, UInt
)] {
  var rows: [(Int, Int, UInt)] = []
  _ = manager.enumerateTextLayoutFragments(
    from: manager.documentRange.location, options: [.ensuresLayout]
  ) { f in
    guard let location = f.textElement?.elementRange?.location else { return false }
    let start = content.offset(from: content.documentRange.location, to: location)
    for line in f.textLineFragments {
      rows.append(
        (
          start + line.characterRange.location, line.characterRange.length,
          line.typographicBounds.width.bitPattern
        ))
    }
    return true
  }
  return rows
}

@MainActor func nativePlan(
  _ source: NSAttributedString, width: CGFloat, direction: NSWritingDirection
) -> [LineSpan] {
  let mutable = NSMutableAttributedString(attributedString: source)
  let style =
    (source.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?
    .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
  style.baseWritingDirection = direction
  mutable.addAttribute(
    .paragraphStyle, value: style, range: NSRange(location: 0, length: mutable.length))
  let content = NSTextContentStorage()
  let storage = NSTextStorage(attributedString: mutable)
  content.textStorage = storage
  let manager = NSTextLayoutManager()
  content.addTextLayoutManager(manager)
  content.primaryTextLayoutManager = manager
  manager.textContainer = NSTextContainer(
    size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
  manager.ensureLayout(for: manager.documentRange)
  var spans: [LineSpan] = []
  _ = manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: []) {
    fragment in
    guard let range = fragment.textElement?.elementRange else { return false }
    let base = content.offset(from: content.documentRange.location, to: range.location)
    for line in fragment.textLineFragments {
      spans.append(
        LineSpan(start: base + line.characterRange.location, length: line.characterRange.length))
    }
    return true
  }
  return spans
}

@MainActor func incrementalSpans(
  _ original: [LineSpan], edited: NSAttributedString, position: Int, width: CGFloat, window: Int,
  direction: NSWritingDirection, maximumWindows: Int = .max
) -> (spans: [LineSpan], windows: Int, convergence: Int) {
  let delta = edited.length - (original.last.map { $0.start + $0.length } ?? 0)
  let startIndex = max(0, original.lastIndex(where: { $0.start <= position }) ?? 0)
  let prefix = Array(original.prefix(startIndex))
  let oldByStart = Dictionary(
    uniqueKeysWithValues: original.enumerated().map { ($0.element.start, $0.offset) })
  var cursor = original[startIndex].start
  var localAll: [LineSpan] = []
  var windows = 0
  while cursor < edited.length && windows < maximumWindows {
    let n = min(window, edited.length - cursor)
    let part = edited.attributedSubstring(from: NSRange(location: cursor, length: n))
    var local = nativePlan(part, width: width, direction: direction).map {
      LineSpan(start: cursor + $0.start, length: $0.length)
    }
    if cursor + n < edited.length && local.count > 1 { local.removeLast() }
    guard let last = local.last else { break }
    localAll.append(contentsOf: local)
    windows += 1
    if localAll.count >= 2 {
      let firstCandidate = max(0, localAll.count - 6)
      for j in firstCandidate..<(localAll.count - 1) {
        let a = localAll[j]
        let b = localAll[j + 1]
        guard a.start >= position + delta,
          let oldA = oldByStart[a.start - delta], oldA + 1 < original.count
        else { continue }
        if original[oldA].length == a.length,
          original[oldA + 1].start + delta == b.start,
          original[oldA + 1].length == b.length
        {
          let rebuilt =
            prefix + Array(localAll.prefix(j + 2))
            + original.dropFirst(oldA + 2).map {
              LineSpan(start: $0.start + delta, length: $0.length)
            }
          return (rebuilt, windows, localAll[j].start)
        }
      }
    }
    cursor = last.start + last.length
  }
  return (prefix + localAll, windows, 0)
}

func groupedSpans(_ lines: [LineSpan], maximumLength: Int) -> [LineSpan] {
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

@MainActor func verifySmallGeometry(
  _ name: String, text: String, reflowWindow: Int, wholeSuffixCoreText: Bool
) throws {
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let source = NSAttributedString(
    string: text, attributes: [.font: font, .paragraphStyle: style])
  let hasCombining = text.unicodeScalars.contains {
    CharacterSet.nonBaseCharacters.contains($0)
  }
  let spans = plannedSpans(source, width: 858, cap: hasCombining ? 8192 : 65536)

  let nativeContent = NSTextContentStorage()
  nativeContent.textStorage = NSTextStorage(attributedString: source)
  let nativePresenter = ParagraphDirectionPresenter()
  nativeContent.delegate = nativePresenter
  let nativeManager = NSTextLayoutManager()
  nativeContent.addTextLayoutManager(nativeManager)
  nativeContent.primaryTextLayoutManager = nativeManager
  nativeManager.textContainer = NSTextContainer(
    size: NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude))
  nativeManager.ensureLayout(for: nativeManager.documentRange)
  let nativeRows = geometry(nativeManager, content: nativeContent)

  let content = PlannedContentStorage()
  content.textStorage = NSTextStorage(attributedString: source)
  content.setSpans(groupedSpans(spans, maximumLength: 2048))
  content.setWholeSuffixCoreTextReplan(wholeSuffixCoreText)
  let presenter = ParagraphDirectionPresenter()
  content.delegate = presenter
  let manager = NSTextLayoutManager()
  content.addTextLayoutManager(manager)
  content.primaryTextLayoutManager = manager
  manager.textContainer = NSTextContainer(
    size: NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude))
  let editor = NSTextView(
    frame: NSRect(x: 0, y: 0, width: 900, height: 500), textContainer: manager.textContainer)
  let window = NSWindow(
    contentRect: editor.frame, styleMask: .borderless, backing: .buffered, defer: false)
  window.contentView = editor
  guard editor.textContentStorage === content else {
    throw NSError(domain: "observer-probe", code: 30)
  }
  manager.ensureLayout(for: manager.documentRange)
  let observedRows = geometry(manager, content: content)
  let exact =
    nativeRows.count == observedRows.count
    && zip(nativeRows, observedRows).allSatisfy {
      $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2
    }
  guard exact else { throw NSError(domain: "observer-probe", code: 31) }
  editor.allowsUndo = true
  editor.font = font
  editor.typingAttributes = [.font: font, .paragraphStyle: style]
  let before = editor.string
  let insertion = before.utf16.count / 2
  editor.setSelectedRange(NSRange(location: insertion, length: 0))
  editor.insertText("X", replacementRange: NSRange(location: insertion, length: 0))
  let edited = editor.string
  let editedSource = NSAttributedString(
    string: edited, attributes: [.font: font, .paragraphStyle: style])
  let nativeEditedContent = NSTextContentStorage()
  nativeEditedContent.textStorage = NSTextStorage(attributedString: editedSource)
  let nativeEditedPresenter = ParagraphDirectionPresenter()
  nativeEditedContent.delegate = nativeEditedPresenter
  let nativeEditedManager = NSTextLayoutManager()
  nativeEditedContent.addTextLayoutManager(nativeEditedManager)
  nativeEditedContent.primaryTextLayoutManager = nativeEditedManager
  nativeEditedManager.textContainer = NSTextContainer(
    size: NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude))
  nativeEditedManager.ensureLayout(for: nativeEditedManager.documentRange)
  let nativeEditedRows = geometry(nativeEditedManager, content: nativeEditedContent)
  let reflowStart = ContinuousClock.now
  let nativeReflow =
    wholeSuffixCoreText
    ? (spans: content.spansSnapshot(), windows: 0, convergence: 0)
    : incrementalSpans(
      spans, edited: editedSource, position: insertion, width: 868, window: reflowWindow,
      direction: name == "rtl-emoji" ? .rightToLeft : .leftToRight)
  if !wholeSuffixCoreText {
    content.setSpans(groupedSpans(nativeReflow.spans, maximumLength: 2048))
  }
  manager.invalidateLayout(for: manager.documentRange)
  manager.ensureLayout(for: manager.documentRange)
  let reflowElapsed = reflowStart.duration(to: .now).components
  let reflowMilliseconds =
    Double(reflowElapsed.seconds) * 1_000
    + Double(reflowElapsed.attoseconds) / 1e15
  let observedEditedRows = geometry(manager, content: content)
  let editedExact =
    nativeEditedRows.count == observedEditedRows.count
    && zip(nativeEditedRows, observedEditedRows).allSatisfy {
      $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2
    }
  let editedFirstDiff = zip(nativeEditedRows, observedEditedRows).enumerated().first {
    $0.element.0 != $0.element.1
  }
  let editedDiffs = zip(nativeEditedRows, observedEditedRows).enumerated().filter {
    $0.element.0 != $0.element.1
  }
  fputs(
    "editGeometry=\(name) strategy=\(wholeSuffixCoreText ? "coretext-whole-suffix" : "native-bounded") reflowWindows=\(nativeReflow.windows) convergence=\(nativeReflow.convergence) reflowMs=\(reflowMilliseconds) diffCount=\(editedDiffs.count) first=\(String(describing: editedFirstDiff)) last=\(String(describing: editedDiffs.last))\n",
    stderr)
  fputs(
    "editGeometry=\(name) exact=\(editedExact) nativeRows=\(nativeEditedRows.count) customRows=\(observedEditedRows.count) firstDiff=\(String(describing: editedFirstDiff))\n",
    stderr)
  print(
    "geometryControl=\(name) units=\(source.length) nativeRows=\(nativeRows.count) plannedRows=\(observedRows.count) initialExact=\(exact) editedRows=\(observedEditedRows.count) editedExact=\(editedExact)"
  )
  guard editedExact, edited.utf16.count == before.utf16.count + 1 else {
    throw NSError(domain: "observer-probe", code: 32)
  }
  editor.undoManager?.undo()
  guard editor.string.utf16.elementsEqual(before.utf16) else {
    throw NSError(domain: "observer-probe", code: 33)
  }
  withExtendedLifetime((window, nativePresenter, presenter, nativeEditedPresenter)) {}

}

@MainActor func largeTarget(
  _ target: String, reflowWindow: Int, maximumReflowWindows: Int,
  wholeSuffixCoreText: Bool
) throws {
  let header = "123456789012345\n"
  let unit = "خط📝"
  let bytes = 10_485_760
  let text = header + String(repeating: unit, count: (bytes - header.utf8.count) / unit.utf8.count)
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let source = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
  guard source.string.utf8.count == bytes else { throw NSError(domain: "probe", code: 9) }
  let planStart = ContinuousClock.now
  let spans = plannedSpans(source, width: 858, cap: 65536)
  let planElapsed = planStart.duration(to: .now)
  let backing = NSTextStorage(attributedString: source)
  let customContent = PlannedContentStorage()
  customContent.textStorage = backing
  customContent.setSpans(groupedSpans(spans, maximumLength: 2048))
  customContent.setWholeSuffixCoreTextReplan(wholeSuffixCoreText)
  let paragraphPresenter = ParagraphDirectionPresenter()
  customContent.delegate = paragraphPresenter
  let customManager = NSTextLayoutManager()
  customContent.addTextLayoutManager(customManager)
  customContent.primaryTextLayoutManager = customManager
  let customContainer = NSTextContainer(
    size: NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude))
  customManager.textContainer = customContainer
  let editor = NSTextView(
    frame: NSRect(x: 0, y: 0, width: 900, height: 500), textContainer: customContainer)
  editor.textContainerInset = NSSize(width: 16, height: 16)
  editor.isRichText = false
  let window = NSWindow(
    contentRect: editor.frame, styleMask: .borderless, backing: .buffered, defer: false)
  window.contentView = editor
  let total = backing.length
  editor.allowsUndo = true
  editor.font = font
  editor.typingAttributes = [.font: font, .paragraphStyle: style]
  _ = window.makeFirstResponder(editor)
  let before = editor.string
  let insertion = total / 2
  editor.setSelectedRange(NSRange(location: insertion, length: 0))
  var eventSamples: [Double] = []
  let inputCount = wholeSuffixCoreText ? 1 : 20
  for _ in 0..<inputCount {
    guard
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, characters: "X", charactersIgnoringModifiers: "X", isARepeat: false,
        keyCode: 7
      )
    else { throw NSError(domain: "observer-probe", code: 20) }
    let started = ContinuousClock.now
    window.sendEvent(event)
    let elapsed = started.duration(to: .now).components
    eventSamples.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
    editor.breakUndoCoalescing()
  }
  var expectedUnits = Array(before.utf16)
  expectedUnits.insert(contentsOf: repeatElement(UInt16(88), count: inputCount), at: insertion)
  let expected = String(decoding: expectedUnits, as: UTF16.self)
  let edited = editor.string
  let eventExact = edited.utf16.elementsEqual(expected.utf16)
  let selectionExact =
    editor.selectedRange() == NSRange(location: insertion + inputCount, length: 0)
  let editedSource = NSAttributedString(
    string: edited, attributes: [.font: font, .paragraphStyle: style])
  let reflowStart = ContinuousClock.now
  let reflow =
    wholeSuffixCoreText
    ? (spans: customContent.spansSnapshot(), windows: 0, convergence: 0)
    : incrementalSpans(
      spans, edited: editedSource, position: insertion, width: 868, window: reflowWindow,
      direction: .rightToLeft, maximumWindows: maximumReflowWindows)
  let reflowCoversDocument =
    reflow.spans.last.map { $0.start + $0.length } == edited.utf16.count
  if !wholeSuffixCoreText && (reflow.convergence != 0 || reflowCoversDocument) {
    customContent.setSpans(groupedSpans(reflow.spans, maximumLength: 2048))
    customManager.invalidateLayout(for: customManager.documentRange)
  }
  let reflowElapsed = reflowStart.duration(to: .now).components
  let reflowMilliseconds =
    Double(reflowElapsed.seconds) * 1_000
    + Double(reflowElapsed.attoseconds) / 1e15
  let updatedSpans = customContent.spansSnapshot()
  let spansCoverDocument =
    updatedSpans.first?.start == 0
    && updatedSpans.last.map { $0.start + $0.length } == edited.utf16.count
    && zip(updatedSpans, updatedSpans.dropFirst()).allSatisfy { $0.start + $0.length == $1.start }
  let sorted = eventSamples.sorted()
  let median =
    sorted.count.isMultiple(of: 2)
    ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    : sorted[sorted.count / 2]
  let p95 = sorted[max(0, (sorted.count * 95 + 99) / 100 - 1)]
  let editedLayoutStart = customContent.location(
    customContent.documentRange.location, offsetBy: insertion)
  let editedLayoutEnd = customContent.location(
    customContent.documentRange.location, offsetBy: min(edited.utf16.count, insertion + 512))
  var editedLayoutCovered = false
  var laidOutLineCount = 0
  var coveredThrough = insertion
  if let editedLayoutStart, let editedLayoutEnd,
    let range = NSTextRange(location: editedLayoutStart, end: editedLayoutEnd)
  {
    customManager.ensureLayout(for: range)
    _ = customManager.enumerateTextLayoutFragments(
      from: editedLayoutStart, options: [.ensuresLayout]
    ) { fragment in
      guard let elementRange = fragment.textElement?.elementRange else { return false }
      let elementStart = elementRange.location
      let base = customContent.offset(from: customContent.documentRange.location, to: elementStart)
      for line in fragment.textLineFragments {
        let lineStart = base + line.characterRange.location
        laidOutLineCount += 1
        if lineStart <= coveredThrough && lineStart + line.characterRange.length > coveredThrough {
          coveredThrough = lineStart + line.characterRange.length
        }
      }
      return coveredThrough < insertion + inputCount
    }
    editedLayoutCovered = coveredThrough >= insertion + inputCount
  }
  print(
    "editAtMiddle=\(insertion) planMs=\(planElapsed * 1000) events=\(eventSamples.count) medianMs=\(median) p95Ms=\(p95) strategy=\(wholeSuffixCoreText ? "coretext-whole-suffix" : "native-bounded") nativeReflowWindows=\(reflow.windows) nativeReflowConvergence=\(reflow.convergence) nativeReflowCoversDocument=\(reflowCoversDocument) nativeReflowMs=\(reflowMilliseconds) selectionExact=\(selectionExact) textExact=\(eventExact) spansCoverDocument=\(spansCoverDocument) lineCount=\(laidOutLineCount) coveredThrough=\(coveredThrough) fragmentsCovered=\(editedLayoutCovered) managerAttached=\(editor.textContentStorage === customContent)"
  )
  guard eventExact, selectionExact, spansCoverDocument, editedLayoutCovered,
    editor.textContentStorage === customContent
  else { throw NSError(domain: "observer-probe", code: 21) }
  for _ in 0..<inputCount { editor.undoManager?.undo() }
  let undoExact = editor.string.utf16.elementsEqual(before.utf16)
  let undoCaretExact = editor.selectedRange().location == insertion
  let undoSpans = customContent.spansSnapshot()
  let undoSpansCover =
    undoSpans.first?.start == 0
    && undoSpans.last.map { $0.start + $0.length } == before.utf16.count
    && zip(undoSpans, undoSpans.dropFirst()).allSatisfy { $0.start + $0.length == $1.start }
  print("undoExact=\(undoExact) undoCaret=\(undoCaretExact) undoSpansCover=\(undoSpansCover)")
  guard undoExact, undoCaretExact, undoSpansCover else {
    throw NSError(domain: "observer-probe", code: 22)
  }
  withExtendedLifetime(window) {}
}

@main @MainActor enum Main {
  static func main() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let arguments = Array(CommandLine.arguments.dropFirst())
    let reflowWindow = arguments.first.flatMap(Int.init) ?? 8192
    let maximumReflowWindows = arguments.dropFirst().first.flatMap(Int.init) ?? 16
    let smallReflowWindow = arguments.dropFirst(2).first.flatMap(Int.init) ?? 8192
    let wholeSuffixCoreText = arguments.dropFirst(3).contains("coretext-suffix")
    let largeOnly = arguments.contains("large-only")
    guard (1...65_536).contains(reflowWindow), (1...2_000).contains(maximumReflowWindows),
      (1...65_536).contains(smallReflowWindow)
    else {
      throw NSError(domain: "observer-probe", code: 40)
    }
    if !largeOnly {
      try verifySmallGeometry(
        "rtl-emoji", text: String(repeating: "خط📝", count: 30_000),
        reflowWindow: smallReflowWindow, wholeSuffixCoreText: wholeSuffixCoreText)
      try verifySmallGeometry(
        "mixed-scripts", text: String(repeating: "abc اردو 123 — שלום🙂 ", count: 5_500),
        reflowWindow: smallReflowWindow, wholeSuffixCoreText: wholeSuffixCoreText)
      try verifySmallGeometry(
        "combining", text: String(repeating: "e\u{301} العربية العربية אבג 🧑🏽‍💻 ", count: 4_000),
        reflowWindow: smallReflowWindow, wholeSuffixCoreText: wholeSuffixCoreText)
    }
    try largeTarget(
      "all", reflowWindow: reflowWindow, maximumReflowWindows: maximumReflowWindows,
      wholeSuffixCoreText: wholeSuffixCoreText)
  }
}
