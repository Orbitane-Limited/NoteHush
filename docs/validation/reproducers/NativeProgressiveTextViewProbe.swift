@preconcurrency import AppKit
import CoreText
import Foundation
import os

@MainActor
private final class NativeLineChunkPlanner {
  struct Result {
    let range: Range<Int>
    let lineCount: Int
  }

  private let source: NSAttributedString
  private let width: CGFloat
  private let maximumLength: Int
  private(set) var results: [Result] = []
  private(set) var nextOffset = 0

  init(source: NSAttributedString, width: CGFloat, maximumLength: Int) {
    self.source = source
    self.width = width
    self.maximumLength = maximumLength
  }

  var isComplete: Bool { nextOffset == source.length }

  func planNext() throws -> Result? {
    guard nextOffset < source.length else { return nil }
    let candidateLength = min(maximumLength, source.length - nextOffset)
    let candidate = source.attributedSubstring(
      from: NSRange(location: nextOffset, length: candidateLength))
    var lineEnds: [Int] = []
    let typesetter = CTTypesetterCreateWithAttributedString(candidate as CFAttributedString)
    var offset = 0
    while offset < candidate.length {
      let count = CTTypesetterSuggestLineBreak(typesetter, offset, Double(width))
      guard count > 0 else { throw NSError(domain: "progressive-probe", code: 1) }
      offset += count
      lineEnds.append(offset)
    }
    guard !lineEnds.isEmpty else { throw NSError(domain: "progressive-probe", code: 2) }

    let candidateEnd = nextOffset + candidateLength
    var end = candidateEnd
    if candidateEnd < source.length, lineEnds.count > 1 {
      end = nextOffset + lineEnds[lineEnds.count - 2]
    }
    if end > 0, end < source.length {
      let composed = (source.string as NSString).rangeOfComposedCharacterSequence(at: end)
      if composed.location < end { end = composed.location }
    }
    guard end > nextOffset else { throw NSError(domain: "progressive-probe", code: 3) }

    let result = Result(
      range: nextOffset..<end,
      lineCount: lineEnds.filter { $0 <= end - nextOffset }.count)
    nextOffset = end
    results.append(result)
    return result
  }

  func plan(upTo offset: Int) throws {
    while nextOffset < min(offset, source.length) { _ = try planNext() }
  }
}

@MainActor
private final class ProgressiveNativeContentStorage: NSTextContentStorage {
  private let plannedRanges = OSAllocatedUnfairLock(initialState: [Range<Int>]())
  private let knownLocations = OSAllocatedUnfairLock(initialState: [ObjectIdentifier: Int]())
  private let emitted = OSAllocatedUnfairLock(initialState: 0)

  var emittedElementCount: Int { emitted.withLock { $0 } }
  var plannedRangesSnapshot: [Range<Int>] { plannedRanges.withLock { $0 } }

  override var documentRange: NSTextRange {
    let range = super.documentRange
    remember(range.location, 0)
    remember(range.endLocation, textStorage?.length ?? 0)
    return range
  }

  required init?(coder: NSCoder) { nil }
  override init() { super.init() }

  func append(_ range: Range<Int>) -> Bool {
    let maximumLength = textStorage?.length ?? 0
    return plannedRanges.withLock { ranges in
      let expected = ranges.last?.upperBound ?? 0
      guard range.lowerBound == expected, range.upperBound <= maximumLength else {
        return false
      }
      ranges.append(range)
      return true
    }
  }

  nonisolated private func remember(_ location: any NSTextLocation, _ offset: Int) {
    knownLocations.withLock { $0[ObjectIdentifier(location as AnyObject)] = offset }
  }

  nonisolated private func offset(for location: any NSTextLocation) -> Int? {
    knownLocations.withLock { $0[ObjectIdentifier(location as AnyObject)] }
  }

  nonisolated override func enumerateTextElements(
    from textLocation: (any NSTextLocation)?,
    options: NSTextContentManager.EnumerationOptions,
    using block: (NSTextElement) -> Bool
  ) -> (any NSTextLocation)? {
    guard let storage = textStorage else { return nil }
    let base = super.documentRange.location
    let total = storage.length
    let reverse = options.contains(.reverse)
    remember(base, 0)
    let endLocation = super.location(base, offsetBy: total)
    if let endLocation { remember(endLocation, total) }
    let requested = textLocation.flatMap(offset(for:)) ?? (reverse ? total : 0)
    let ranges = plannedRanges.withLock { $0 }
    let indices = reverse ? Array(ranges.indices.reversed()) : Array(ranges.indices)
    var last = textLocation ?? (reverse ? endLocation : base)

    for index in indices {
      let range = ranges[index]
      guard reverse ? range.lowerBound < requested : range.upperBound > requested else { continue }
      guard
        let start = super.location(base, offsetBy: range.lowerBound),
        let end = super.location(base, offsetBy: range.upperBound),
        let elementRange = NSTextRange(location: start, end: end)
      else { return nil }
      remember(start, range.lowerBound)
      remember(end, range.upperBound)
      let attributed = storage.attributedSubstring(
        from: NSRange(location: range.lowerBound, length: range.count))
      let paragraph = NSTextParagraph(attributedString: attributed)
      paragraph.textContentManager = self
      paragraph.elementRange = elementRange
      emitted.withLock { $0 += 1 }
      last = reverse ? start : end
      if !block(paragraph) { return last }
    }
    return last
  }

  nonisolated override func location(
    _ location: any NSTextLocation, offsetBy offset: Int
  ) -> (any NSTextLocation)? {
    guard let known = self.offset(for: location),
      let result = super.location(location, offsetBy: offset)
    else { return nil }
    remember(result, known + offset)
    return result
  }

  nonisolated override func offset(
    from: any NSTextLocation, to: any NSTextLocation
  ) -> Int {
    guard let start = offset(for: from), let end = offset(for: to) else { return NSNotFound }
    return end - start
  }
}

@main
@MainActor
enum NativeProgressiveTextViewProbe {
  static func main() throws {
    let unit = "خط📝"
    let header = "123456789012345\n"
    let byteCount = 10_485_760
    let repetitions = (byteCount - header.utf8.count) / unit.utf8.count
    let text = header + String(repeating: unit, count: repetitions)
    let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    let style = NSMutableParagraphStyle()
    style.baseWritingDirection = .natural
    let source = NSAttributedString(
      string: text, attributes: [.font: font, .paragraphStyle: style])

    let planner = NativeLineChunkPlanner(source: source, width: 868, maximumLength: 65_536)
    let content = ProgressiveNativeContentStorage()
    let backing = NSTextStorage(attributedString: source)
    content.textStorage = backing
    var plannedLines = 0
    while plannedLines < 48, let result = try planner.planNext() {
      guard content.append(result.range) else { throw NSError(domain: "probe", code: 4) }
      plannedLines += result.lineCount
    }

    let layout = NSTextLayoutManager()
    content.addTextLayoutManager(layout)
    content.primaryTextLayoutManager = layout
    let container = NSTextContainer(
      size: NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    layout.textContainer = container
    let editor = NSTextView(
      frame: NSRect(x: 0, y: 0, width: 900, height: 500), textContainer: container)
    editor.isRichText = false
    editor.allowsUndo = true
    editor.textContainerInset = NSSize(width: 16, height: 16)
    editor.font = font
    NSApplication.shared.setActivationPolicy(.prohibited)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
    scroll.hasVerticalScroller = true
    scroll.documentView = editor
    let window = NSWindow(
      contentRect: scroll.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = scroll
    let firstResponder = window.makeFirstResponder(editor)

    guard editor.textContentStorage === content, editor.textLayoutManager === layout else {
      throw NSError(domain: "probe", code: 5)
    }
    let initialRange = content.plannedRangesSnapshot.last?.upperBound ?? 0
    let initialStart = ProcessInfo.processInfo.systemUptime
    guard let firstEnd = content.location(content.documentRange.location, offsetBy: initialRange),
      let firstRange = NSTextRange(location: content.documentRange.location, end: firstEnd)
    else { throw NSError(domain: "probe", code: 6) }
    layout.ensureLayout(for: firstRange)
    let initialMilliseconds = (ProcessInfo.processInfo.systemUptime - initialStart) * 1_000
    print(
      "initial textview=attached firstResponder=\(firstResponder) planned=\(initialRange) " +
        "layoutMs=\(initialMilliseconds) chunks=\(planner.results.count) " +
        "emitted=\(content.emittedElementCount) textExact=\(editor.string.utf16.elementsEqual(text.utf16))")

    let target = source.length / 2
    let planningStart = ProcessInfo.processInfo.systemUptime
    try planner.plan(upTo: target + 4_096)
    for result in planner.results.dropFirst(content.plannedRangesSnapshot.count) {
      guard content.append(result.range) else { throw NSError(domain: "probe", code: 7) }
    }
    let planningMilliseconds = (ProcessInfo.processInfo.systemUptime - planningStart) * 1_000
    guard let targetStart = content.location(content.documentRange.location, offsetBy: target),
      let targetEnd = content.location(content.documentRange.location, offsetBy: min(source.length, target + 2_048)),
      let targetRange = NSTextRange(location: content.documentRange.location, end: targetEnd)
    else { throw NSError(domain: "probe", code: 8) }
    layout.ensureLayout(for: targetRange)
    let targetFragment = layout.textLayoutFragment(for: targetStart)
    print(
      "middle planned=\(planner.nextOffset) planMs=\(planningMilliseconds) " +
        "prefixLayoutMs=\((ProcessInfo.processInfo.systemUptime - planningStart) * 1_000) " +
        "fragment=\(targetFragment != nil) frameY=\(targetFragment?.layoutFragmentFrame.minY ?? -1) " +
        "chunks=\(planner.results.count) emitted=\(content.emittedElementCount)")
    window.close()
  }
}
