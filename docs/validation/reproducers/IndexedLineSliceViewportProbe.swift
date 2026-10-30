@preconcurrency import AppKit
import CoreText
import Foundation

private struct IndexedLine: Sendable {
  let range: Range<Int>
  let y: CGFloat
  let height: CGFloat
  let width: Double
}

@MainActor
private struct GeometryRow: Equatable {
  let start: Int
  let length: Int
  let width: Double
  let height: Double
}

private struct LinePlan: Sendable {
  let lines: [IndexedLine]
  let height: CGFloat
}

/// A worker result transferred under an explicit lock after the group signals completion.
private final class PlanResultBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Result<LinePlan, Error>?

  func store(_ result: Result<LinePlan, Error>) {
    lock.lock()
    defer { lock.unlock() }
    stored = result
  }

  func load() -> Result<LinePlan, Error>? {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }
}

@MainActor
private func nativeGeometry(_ source: NSAttributedString, width: CGFloat) throws -> [GeometryRow] {
  let storage = NSTextStorage(attributedString: source)
  let content = NSTextContentStorage()
  content.textStorage = storage
  let manager = NSTextLayoutManager()
  content.addTextLayoutManager(manager)
  content.primaryTextLayoutManager = manager
  manager.textContainer = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
  let range = manager.documentRange
  manager.ensureLayout(for: range)
  var rows: [GeometryRow] = []
  _ = manager.enumerateTextLayoutFragments(from: range.location, options: [.ensuresLayout]) { fragment in
    guard let elementRange = fragment.textElement?.elementRange else { return true }
    let base = content.offset(from: range.location, to: elementRange.location)
    guard base != NSNotFound, base >= 0 else { return true }
    for line in fragment.textLineFragments {
      rows.append(
        GeometryRow(
          start: base + line.characterRange.location,
          length: line.characterRange.length,
          width: Double(line.typographicBounds.width),
          height: Double(line.typographicBounds.height)))
    }
    return true
  }
  return rows
}

@MainActor
private func checkSmallGeometry() throws {
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let hardSeparatorSample = [
    "עברית 12 e\u{301}\n",
    "العربية🙂 3\r\n",
    "abc\r\u{0085}NEL\u{2028}LS\u{2029}PS ",
  ].joined()
  let fixtures = [
    ("rtl-emoji", String(repeating: "خط📝", count: 2_000), 320.0, 65_536),
    ("mixed-bidi", String(repeating: "abc اردو 123 — שלום🙂 ", count: 600), 420.0, 65_536),
    ("combining", String(repeating: "e\u{301} العربية אבג 🧑🏽‍💻 ", count: 600), 420.0, 8_192),
    ("punctuation", String(repeating: "(rtl: العربية 42) [עברית, 7] — 🙂 ", count: 600), 420.0, 65_536),
    (
      "hard-separators",
      String(repeating: hardSeparatorSample, count: 200),
      360.0, 8_192
    ),
  ]
  for (name, text, width, window) in fixtures {
    let source = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
    let plan = try makePlan(source, width: width, window: window)
    let framePlan = try makeFramePlan(source, width: width, window: window)
    let expected = try nativeGeometry(source, width: width)
    guard framePlan.lines.map(\.range) == plan.lines.map(\.range),
      framePlan.lines.map(\.height) == plan.lines.map(\.height)
    else {
      throw NSError(domain: "line-index", code: 19, userInfo: [NSLocalizedDescriptionKey: "\(name): framesetter geometry differs from typesetter plan"])
    }
    guard plan.lines.count == expected.count else {
      throw NSError(domain: "line-index", code: 9, userInfo: [NSLocalizedDescriptionKey: "\(name): CoreText lines \(plan.lines.count), native TextKit lines \(expected.count)"])
    }
    var maxWidthDelta = 0.0
    var maxHeightDelta = 0.0
    for (indexed, native) in zip(plan.lines, expected) {
      let indexedWidth = indexed.width
      let nativeWidth = native.width
      maxWidthDelta = max(maxWidthDelta, abs(indexedWidth - nativeWidth))
      maxHeightDelta = max(maxHeightDelta, abs(Double(indexed.height) - native.height))
      guard indexed.range.lowerBound == native.start,
        indexed.range.count == native.length
      else {
        throw NSError(domain: "line-index", code: 10, userInfo: [NSLocalizedDescriptionKey: "\(name): geometry mismatch at \(indexed.range), native \(native.start)..<\(native.start + native.length), widths \(indexedWidth)/\(nativeWidth)"])
      }
    }
    let sampleStarts = Set([0, plan.lines.count / 2, max(0, plan.lines.count - 64)])
    for first in sampleStarts {
      let last = min(plan.lines.count, first + 64)
      let sliceStart = plan.lines[first].range.lowerBound
      let sliceEnd = plan.lines[last - 1].range.upperBound
      let slice = source.attributedSubstring(from: NSRange(location: sliceStart, length: sliceEnd - sliceStart))
      var localRows = try nativeGeometry(slice, width: width)
      // A slice ending exactly at a hard separator can expose a terminal empty
      // TextKit line that is not present at this point in the complete source.
      while localRows.last?.start == slice.length, localRows.last?.length == 0 {
        localRows.removeLast()
      }
      guard localRows.count == last - first else {
        let detail =
          "\(name): slice at line \(first), source \(sliceStart)..<\(sliceEnd), has \(localRows.count) lines, expected \(last - first)"
        throw NSError(
          domain: "line-index", code: 13, userInfo: [NSLocalizedDescriptionKey: detail])
      }
      for (offset, localRow) in localRows.enumerated() {
        let expectedRow = expected[first + offset]
        guard localRow.start + sliceStart == expectedRow.start,
          localRow.length == expectedRow.length,
          abs(localRow.width - expectedRow.width) <= 0.01,
          abs(localRow.height - expectedRow.height) <= 0.01
        else {
          throw NSError(domain: "line-index", code: 14, userInfo: [NSLocalizedDescriptionKey: "\(name): sliced native TextKit differs from full document at line \(first + offset)"])
        }
      }
    }
    print("geometryFixture=\(name) utf16=\(source.length) lines=\(plan.lines.count) maxCoreTextWidthDelta=\(maxWidthDelta) maxHeightDelta=\(maxHeightDelta) slices=start/middle/end result=match")
  }
}

@MainActor
private func visibleGlyphPixelCount(_ view: NSView, y: CGFloat, height: CGFloat) throws -> Int {
  let rect = NSRect(x: 0, y: y, width: view.bounds.width, height: height)
  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(rect.width), pixelsHigh: Int(rect.height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
  else { throw NSError(domain: "line-index", code: 11) }
  view.cacheDisplay(in: rect, to: bitmap)
  var count = 0
  for pixelY in 0..<bitmap.pixelsHigh {
    for pixelX in 0..<bitmap.pixelsWide {
      guard let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB) else { continue }
      if color.redComponent < 0.70 && color.greenComponent < 0.70 && color.blueComponent < 0.70 { count += 1 }
    }
  }
  return count
}

@MainActor
private func measureVisibleSliceEdits(_ source: NSAttributedString, width: CGFloat) throws
  -> (Duration, Duration, String)
{
  let storage = NSTextStorage(attributedString: source)
  let content = NSTextContentStorage()
  content.textStorage = storage
  let manager = NSTextLayoutManager()
  content.addTextLayoutManager(manager)
  content.primaryTextLayoutManager = manager
  manager.textContainer = NSTextContainer(size: NSSize(width: width - 10, height: .greatestFiniteMagnitude))
  let original = storage.string
  let originalLength = storage.length
  let nsSource = original as NSString
  let composition = nsSource.rangeOfComposedCharacterSequence(at: originalLength / 2)
  let insertionPoint = NSMaxRange(composition)
  var samples: [Duration] = []
  for index in 0..<20 {
    let insertion = index.isMultiple(of: 2)
    let replacement = insertion ? (index % 4 == 0 ? "🙂" : "x") : ""
    let replacementLength = insertion ? replacement.utf16.count : (index % 4 == 1 ? 2 : 1)
    let range = NSRange(location: insertionPoint, length: insertion ? 0 : replacementLength)
    let attributes = storage.attributes(at: max(0, min(storage.length - 1, insertionPoint - 1)), effectiveRange: nil)
    let attributedReplacement = NSAttributedString(string: replacement, attributes: attributes)
    let started = ContinuousClock.now
    storage.replaceCharacters(in: range, with: attributedReplacement)
    let documentRange = manager.documentRange
    guard let textRange = NSTextRange(location: documentRange.location, end: documentRange.endLocation)
    else { throw NSError(domain: "line-index", code: 24) }
    manager.ensureLayout(for: textRange)
    _ = manager.enumerateTextLayoutFragments(from: textRange.location, options: [.ensuresLayout]) { _ in true }
    samples.append(started.duration(to: .now))
  }
  guard storage.string == original, storage.length == originalLength else {
    throw NSError(domain: "line-index", code: 25, userInfo: [NSLocalizedDescriptionKey: "visible slice edit/undo control changed its source"])
  }
  let sorted = samples.sorted()
  return (sorted[9], sorted[18], "samples=20 min=\(sorted[0]) max=\(sorted[19])")
}

@MainActor
private func makePlan(
  _ source: NSAttributedString, width: CGFloat, window: Int, metricStride: Int? = 1
) throws -> LinePlan {
  let textWidth = max(1, width - 10) // Match NSTextContainer's default 5 point padding on each side.
  var spans: [Range<Int>] = []
  var heightByRange: [Range<Int>: CGFloat] = [:]
  var widthByRange: [Range<Int>: Double] = [:]
  let baseFont = (source.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    .map { $0 as CTFont } ?? CTFontCreateWithName("Menlo" as CFString, 14, nil)
  let baseLineHeight = ceil(CTFontGetAscent(baseFont) + CTFontGetDescent(baseFont) + CTFontGetLeading(baseFont))
  var start = 0
  while start < source.length {
    let count = min(window, source.length - start)
    let candidate = source.attributedSubstring(from: NSRange(location: start, length: count))
    let typesetter = CTTypesetterCreateWithAttributedString(candidate as CFAttributedString)
    var local: [Range<Int>] = []
    var offset = 0
    var localLineIndex = 0
    var sampledHeight = baseLineHeight
    while offset < candidate.length {
      let length = CTTypesetterSuggestLineBreak(typesetter, offset, Double(textWidth))
      guard length > 0 else { throw NSError(domain: "line-index", code: 1) }
      let range = (start + offset)..<(start + offset + length)
      local.append(range)
      if let metricStride, localLineIndex.isMultiple(of: metricStride) {
        let line = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: length))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        sampledHeight = max(1, ceil(ascent + descent + leading))
        heightByRange[range] = sampledHeight
        widthByRange[range] = width
      } else {
        heightByRange[range] = max(1, sampledHeight)
        widthByRange[range] = 0
      }
      offset += length
      localLineIndex += 1
    }
    guard !local.isEmpty else { throw NSError(domain: "line-index", code: 2) }
    if start + count < source.length, local.count > 1 {
      spans.append(contentsOf: local.dropLast())
      start = local[local.count - 2].upperBound
    } else {
      spans.append(contentsOf: local)
      start += count
    }
  }

  var lines: [IndexedLine] = []
  var y: CGFloat = 0
  for range in spans {
    guard let height = heightByRange[range] else { throw NSError(domain: "line-index", code: 7) }
    guard let widthBits = widthByRange[range] else { throw NSError(domain: "line-index", code: 8) }
    lines.append(IndexedLine(range: range, y: y, height: height, width: widthBits))
    y += height
  }
  guard lines.first?.range.lowerBound == 0,
    lines.last?.range.upperBound == source.length,
    zip(lines, lines.dropFirst()).allSatisfy({ $0.range.upperBound == $1.range.lowerBound })
  else { throw NSError(domain: "line-index", code: 3) }
  return LinePlan(lines: lines, height: y)
}

private func makeStringPlan(text: String, fontName: String, width: CGFloat, window: Int) throws
  -> LinePlan
{
  let font = CTFontCreateWithName(fontName as CFString, 14, nil)
  let attributes = [kCTFontAttributeName: font] as CFDictionary
  guard let source = CFAttributedStringCreate(nil, text as CFString, attributes) else {
    throw NSError(domain: "line-index", code: 33)
  }
  let sourceLength = CFAttributedStringGetLength(source)
  let textWidth = max(1, width - 10)
  var spans: [Range<Int>] = []
  var heights: [Range<Int>: CGFloat] = [:]
  var widths: [Range<Int>: Double] = [:]
  var start = 0
  while start < sourceLength {
    let count = min(window, sourceLength - start)
    guard
      let candidate = CFAttributedStringCreateWithSubstring(
        nil, source, CFRange(location: start, length: count))
    else {
      throw NSError(domain: "line-index", code: 34)
    }
    let typesetter = CTTypesetterCreateWithAttributedString(candidate)
    var local: [Range<Int>] = []
    var offset = 0
    while offset < count {
      let length = CTTypesetterSuggestLineBreak(typesetter, offset, Double(textWidth))
      guard length > 0 else { throw NSError(domain: "line-index", code: 35) }
      let range = (start + offset)..<(start + offset + length)
      local.append(range)
      let line = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: length))
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
      heights[range] = max(1, ceil(ascent + descent + leading))
      widths[range] = lineWidth
      offset += length
    }
    guard !local.isEmpty else { throw NSError(domain: "line-index", code: 36) }
    if start + count < sourceLength, local.count > 1 {
      spans.append(contentsOf: local.dropLast())
      start = local[local.count - 2].upperBound
    } else {
      spans.append(contentsOf: local)
      start += count
    }
  }
  var lines: [IndexedLine] = []
  var y: CGFloat = 0
  for range in spans {
    guard let height = heights[range], let lineWidth = widths[range] else {
      throw NSError(domain: "line-index", code: 37)
    }
    lines.append(IndexedLine(range: range, y: y, height: height, width: lineWidth))
    y += height
  }
  guard lines.first?.range.lowerBound == 0,
    lines.last?.range.upperBound == sourceLength,
    zip(lines, lines.dropFirst()).allSatisfy({ $0.range.upperBound == $1.range.lowerBound })
  else { throw NSError(domain: "line-index", code: 38) }
  return LinePlan(lines: lines, height: y)
}

@MainActor
private func makeFramePlan(_ source: NSAttributedString, width: CGFloat, window: Int) throws
  -> LinePlan
{
  let textWidth = max(1, width - 10)
  var spans: [Range<Int>] = []
  var heights: [Range<Int>: CGFloat] = [:]
  var start = 0
  while start < source.length {
    let count = min(window, source.length - start)
    let candidate = source.attributedSubstring(from: NSRange(location: start, length: count))
    let framesetter = CTFramesetterCreateWithAttributedString(candidate as CFAttributedString)
    let path = CGMutablePath()
    path.addRect(CGRect(x: 0, y: 0, width: textWidth, height: 10_000_000))
    let frame = CTFramesetterCreateFrame(
      framesetter, CFRange(location: 0, length: candidate.length), path, nil)
    guard let localLines = CTFrameGetLines(frame) as? [CTLine] else {
      throw NSError(domain: "line-index", code: 21)
    }
    var local: [Range<Int>] = []
    for line in localLines {
      let range = CTLineGetStringRange(line)
      guard range.location >= 0, range.length > 0 else { continue }
      let span = (start + range.location)..<(start + range.location + range.length)
      local.append(span)
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
      heights[span] = max(1, ceil(ascent + descent + leading))
    }
    guard !local.isEmpty else { throw NSError(domain: "line-index", code: 16) }
    if start + count < source.length, local.count > 1 {
      spans.append(contentsOf: local.dropLast())
      start = local[local.count - 2].upperBound
    } else {
      spans.append(contentsOf: local)
      start += count
    }
  }
  var lines: [IndexedLine] = []
  var y: CGFloat = 0
  for range in spans {
    guard let height = heights[range] else { throw NSError(domain: "line-index", code: 17) }
    lines.append(IndexedLine(range: range, y: y, height: height, width: 0))
    y += height
  }
  guard lines.first?.range.lowerBound == 0,
    lines.last?.range.upperBound == source.length,
    zip(lines, lines.dropFirst()).allSatisfy({ $0.range.upperBound == $1.range.lowerBound })
  else {
    throw NSError(domain: "line-index", code: 18, userInfo: [NSLocalizedDescriptionKey: "frame plan coverage length=\(source.length) lines=\(lines.count) first=\(String(describing: lines.first?.range)) last=\(String(describing: lines.last?.range))"])
  }
  return LinePlan(lines: lines, height: y)
}

@MainActor
private func benchmarkPlan(
  _ source: NSAttributedString, width: CGFloat, window: Int, metricStride: Int? = 1
) throws -> (Duration, Int, CGFloat) {
  let started = ContinuousClock.now
  let plan = try makePlan(source, width: width, window: window, metricStride: metricStride)
  return (started.duration(to: .now), plan.lines.count, plan.height)
}

@MainActor
private final class IndexedSliceView: NSView, @preconcurrency NSTextInputClient {
  private let source: NSMutableAttributedString
  private let plan: LinePlan
  private var fragments: [NSTextLayoutFragment] = []
  private var drawOriginY: CGFloat = 0
  private let viewportHeight: CGFloat
  private var localStorage: NSTextStorage?
  private var localContentStorage: NSTextContentStorage?
  private var localLayoutManager: NSTextLayoutManager?
  private var textInputContext: NSTextInputContext?
  private var selection = NSRange(location: 0, length: 0)
  private var marked = NSRange(location: NSNotFound, length: 0)
  private let history = UndoManager()
  private(set) var displayedRange: Range<Int> = 0..<0
  private(set) var displayedLineCount = 0
  var text: String { source.string }

  override var isFlipped: Bool { true }

  init(source: NSAttributedString, plan: LinePlan, width: CGFloat, viewportHeight: CGFloat) {
    self.source = NSMutableAttributedString(attributedString: source)
    self.plan = plan
    self.viewportHeight = viewportHeight
    super.init(frame: NSRect(x: 0, y: 0, width: width, height: max(viewportHeight, plan.height)))
  }

  required init?(coder: NSCoder) { nil }

  override var acceptsFirstResponder: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil { textInputContext = NSTextInputContext(client: self) }
  }

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { textInputContext?.activate() }
    return accepted
  }

  override func resignFirstResponder() -> Bool {
    unmarkText()
    textInputContext?.deactivate()
    return super.resignFirstResponder()
  }

  override func keyDown(with event: NSEvent) {
    if textInputContext?.handleEvent(event) != true { super.keyDown(with: event) }
  }

  override var undoManager: UndoManager? { history }

  func layoutViewport(at documentY: CGFloat, linesToRender: Int = 64) throws {
    let targetY = min(max(0, documentY), max(0, plan.height - viewportHeight))
    var low = 0
    var high = plan.lines.count
    while low < high {
      let mid = (low + high) / 2
      if plan.lines[mid].y + plan.lines[mid].height <= targetY { low = mid + 1 }
      else { high = mid }
    }
    let first = min(low, max(0, plan.lines.count - 1))
    let last = min(plan.lines.count - 1, first + max(1, linesToRender) - 1)
    let start = plan.lines[first].range.lowerBound
    let end = plan.lines[last].range.upperBound
    let local = source.attributedSubstring(from: NSRange(location: start, length: end - start))

    let storage = NSTextStorage(attributedString: local)
    let content = NSTextContentStorage()
    content.textStorage = storage
    let manager = NSTextLayoutManager()
    content.addTextLayoutManager(manager)
    content.primaryTextLayoutManager = manager
    let container = NSTextContainer(size: NSSize(width: bounds.width, height: .greatestFiniteMagnitude))
    manager.textContainer = container
    let documentRange = manager.documentRange
    guard let range = NSTextRange(location: documentRange.location, end: documentRange.endLocation)
    else { throw NSError(domain: "line-index", code: 4) }
    manager.ensureLayout(for: range)

    var next: [NSTextLayoutFragment] = []
    _ = manager.enumerateTextLayoutFragments(from: range.location, options: [.ensuresLayout]) {
      fragment in
      next.append(fragment)
      return true
    }
    let actualLineCount = next.reduce(0) { $0 + $1.textLineFragments.count }
    guard actualLineCount == last - first + 1 else {
      throw NSError(domain: "line-index", code: 5,
        userInfo: [NSLocalizedDescriptionKey: "indexed lines \(last - first + 1), local TextKit lines \(actualLineCount)"])
    }
    fragments = next
    localStorage = storage
    localContentStorage = content
    localLayoutManager = manager
    drawOriginY = plan.lines[first].y
    displayedRange = start..<end
    displayedLineCount = actualLineCount
    needsDisplay = true
  }

  func indexedY(for rangeStart: Int) -> CGFloat {
    plan.lines.first(where: { $0.range.lowerBound == rangeStart })?.y ?? 0
  }

  private func replace(_ range: NSRange, with replacement: String, selection nextSelection: NSRange) {
    guard range.location != NSNotFound, range.location >= displayedRange.lowerBound,
      range.length >= 0, NSMaxRange(range) <= displayedRange.upperBound,
      let localStorage, let manager = localLayoutManager
    else { return }
    let attributes: [NSAttributedString.Key: Any]
    if source.length > 0 {
      let attributeIndex = max(0, min(source.length - 1, range.location - 1))
      attributes = source.attributes(at: attributeIndex, effectiveRange: nil)
    } else {
      attributes = [:]
    }
    let previousText = source.attributedSubstring(from: range).string
    let previousSelection = selection
    let attributedReplacement = NSAttributedString(string: replacement, attributes: attributes)
    source.replaceCharacters(in: range, with: attributedReplacement)
    let localRange = NSRange(location: range.location - displayedRange.lowerBound, length: range.length)
    localStorage.replaceCharacters(in: localRange, with: attributedReplacement)
    displayedRange = displayedRange.lowerBound..<(displayedRange.upperBound + replacement.utf16.count - range.length)
    selection = nextSelection
    history.registerUndo(withTarget: self) { target in
      target.replace(
        NSRange(location: range.location, length: replacement.utf16.count),
        with: previousText, selection: previousSelection)
    }
    let documentRange = manager.documentRange
    guard let textRange = NSTextRange(location: documentRange.location, end: documentRange.endLocation)
    else { return }
    manager.ensureLayout(for: textRange)
    var updated: [NSTextLayoutFragment] = []
    _ = manager.enumerateTextLayoutFragments(from: textRange.location, options: [.ensuresLayout]) { fragment in
      updated.append(fragment)
      return true
    }
    fragments = updated
    needsDisplay = true
    textInputContext?.invalidateCharacterCoordinates()
  }

  func insertText(_ string: Any, replacementRange: NSRange) {
    let value = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    let range = replacementRange.location == NSNotFound
      ? (marked.location == NSNotFound ? selection : marked) : replacementRange
    replace(range, with: value, selection: NSRange(location: range.location + value.utf16.count, length: 0))
    marked = NSRange(location: NSNotFound, length: 0)
  }

  func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    let value = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    let range = replacementRange.location == NSNotFound
      ? (marked.location == NSNotFound ? selection : marked) : replacementRange
    replace(
      range, with: value,
      selection: NSRange(location: range.location + selectedRange.location, length: selectedRange.length))
    marked = NSRange(location: range.location, length: value.utf16.count)
  }

  func unmarkText() { marked = NSRange(location: NSNotFound, length: 0) }
  func selectedRange() -> NSRange { selection }
  func setSelectedRange(_ range: NSRange) { selection = range }
  func markedRange() -> NSRange { marked }
  func hasMarkedText() -> Bool { marked.location != NSNotFound }
  func validAttributesForMarkedText() -> [NSAttributedString.Key] { [.underlineStyle] }

  func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?)
    -> NSAttributedString?
  {
    guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= source.length else { return nil }
    actualRange?.pointee = range
    return source.attributedSubstring(from: range)
  }

  func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
    guard let window, let content = localContentStorage, let manager = localLayoutManager,
      range.location >= displayedRange.lowerBound,
      NSMaxRange(range) <= displayedRange.upperBound,
      let start = content.location(content.documentRange.location, offsetBy: range.location - displayedRange.lowerBound),
      let end = content.location(start, offsetBy: range.length),
      let textRange = NSTextRange(location: start, end: end)
    else { return .zero }
    var result = CGRect.zero
    manager.enumerateTextSegments(in: textRange, type: .standard, options: []) { segment, rect, _, _ in
      if let segment {
        let offset = content.offset(from: content.documentRange.location, to: segment.location)
        actualRange?.pointee = NSRange(location: displayedRange.lowerBound + offset, length: 1)
      }
      result = rect.offsetBy(dx: 0, dy: drawOriginY)
      return false
    }
    return window.convertToScreen(convert(result, to: nil))
  }

  func characterIndex(for point: NSPoint) -> Int {
    guard let window, let content = localContentStorage, let manager = localLayoutManager else { return NSNotFound }
    let viewPoint = convert(window.convertPoint(fromScreen: point), from: nil)
    let localPoint = CGPoint(x: viewPoint.x, y: viewPoint.y - drawOriginY)
    guard let fragment = manager.textLayoutFragment(for: localPoint),
      let elementRange = fragment.textElement?.elementRange,
      let line = fragment.textLineFragments.first(where: { $0.typographicBounds.contains(localPoint) })
    else { return NSNotFound }
    let elementStart = content.offset(from: content.documentRange.location, to: elementRange.location)
    return displayedRange.lowerBound + elementStart + line.characterRange.location
  }

  override func doCommand(by selector: Selector) {}

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.setFillColor(NSColor.textBackgroundColor.cgColor)
    context.fill(dirtyRect)
    for fragment in fragments {
      let origin = fragment.layoutFragmentFrame.origin
      fragment.draw(at: CGPoint(x: origin.x, y: drawOriginY + origin.y), in: context)
    }
  }
}

@main
@MainActor
private enum IndexedLineSliceViewportProbe {
  static func main() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    try checkSmallGeometry()
    let loadStart = ContinuousClock.now
    let header = "123456789012345\n"
    let unit = "خط📝"
    let byteCount = 10_485_760
    let repetitions = (byteCount - header.utf8.count) / unit.utf8.count
    let text = header + String(repeating: unit, count: repetitions)
    guard text.utf8.count == byteCount else { throw NSError(domain: "line-index", code: 6) }
    let style = NSMutableParagraphStyle()
    style.baseWritingDirection = .natural
    let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    let source = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
    let modelReady = ContinuousClock.now
    let previewStart = ContinuousClock.now
    let previewLength = min(8_192, source.length)
    let previewSource = source.attributedSubstring(from: NSRange(location: 0, length: previewLength))
    let previewPlan = try makePlan(previewSource, width: 858, window: 8_192)
    let previewScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
    let previewView = IndexedSliceView(
      source: source, plan: previewPlan, width: 868, viewportHeight: 500)
    previewScroll.documentView = previewView
    let previewWindow = NSWindow(
      contentRect: previewScroll.frame, styleMask: .borderless, backing: .buffered, defer: false)
    previewWindow.contentView = previewScroll
    try previewView.layoutViewport(at: 0)
    let previewGlyphPixels = try visibleGlyphPixelCount(previewView, y: 0, height: 500)
    let previewDuration = previewStart.duration(to: .now)
    guard previewGlyphPixels > 0 else { throw NSError(domain: "line-index", code: 22) }
    print("prefixViewport=utf16=\(previewLength) lines=\(previewView.displayedLineCount) glyphPixels=\(previewGlyphPixels) prefixLayout=\(previewDuration) sourcePreparation=\(loadStart.duration(to: modelReady)) sourceToFirstViewport=\(loadStart.duration(to: .now))")
    previewWindow.close()

    let planStart = ContinuousClock.now
    let plan = try makePlan(source, width: 858, window: 65_536)
    let planDuration = planStart.duration(to: .now)
    let editFirstLine = max(0, plan.lines.count / 2 - 14)
    let editLastLine = min(plan.lines.count, editFirstLine + 28)
    let editStart = plan.lines[editFirstLine].range.lowerBound
    let editEnd = plan.lines[editLastLine - 1].range.upperBound
    let editSlice = source.attributedSubstring(
      from: NSRange(location: editStart, length: editEnd - editStart))
    let (editP50, editP95, editExtremes) = try measureVisibleSliceEdits(editSlice, width: 858)
    print("nativeSliceEditLines=\(editLastLine - editFirstLine) p50=\(editP50) p95=\(editP95) \(editExtremes) sourceRestored=true")
    for windowSize in [262_144, 524_288, 1_048_576] {
      let (duration, lineCount, height) = try benchmarkPlan(source, width: 858, window: windowSize)
      guard lineCount == plan.lines.count, height == plan.height else {
        throw NSError(domain: "line-index", code: 15, userInfo: [NSLocalizedDescriptionKey: "window \(windowSize) changed line count or document height"])
      }
      print("planWindow=\(windowSize) lines=\(lineCount) height=\(height) duration=\(duration)")
    }
    let (breakOnlyDuration, breakOnlyLines, breakOnlyHeight) = try benchmarkPlan(
      source, width: 858, window: 65_536, metricStride: nil)
    print("planMode=font-height lines=\(breakOnlyLines) height=\(breakOnlyHeight) duration=\(breakOnlyDuration)")
    let (sampledDuration, sampledLines, sampledHeight) = try benchmarkPlan(
      source, width: 858, window: 65_536, metricStride: 64)
    print("planMode=sampled-height stride=64 lines=\(sampledLines) height=\(sampledHeight) duration=\(sampledDuration)")
    let frameStart = ContinuousClock.now
    let framePlan = try makeFramePlan(source, width: 858, window: 65_536)
    let frameDuration = frameStart.duration(to: .now)
    guard framePlan.lines.map(\.range) == plan.lines.map(\.range),
      framePlan.lines.map(\.height) == plan.lines.map(\.height)
    else { throw NSError(domain: "line-index", code: 20, userInfo: [NSLocalizedDescriptionKey: "large framesetter plan differs from typesetter plan"]) }
    print("planMode=framesetter lines=\(framePlan.lines.count) height=\(framePlan.height) duration=\(frameDuration)")

    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = false
    let view = IndexedSliceView(source: source, plan: plan, width: 868, viewportHeight: 500)
    scroll.documentView = view
    let window = NSWindow(contentRect: scroll.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = scroll

    let inputView = IndexedSliceView(source: source, plan: plan, width: 868, viewportHeight: 500)
    let middleY = plan.height / 2
    try inputView.layoutViewport(at: middleY, linesToRender: 28)
    let inputLocation = inputView.displayedRange.lowerBound + 100
    inputView.setSelectedRange(NSRange(location: inputLocation, length: 0))
    let baselineText = inputView.text
    let backgroundResult = PlanResultBox()
    let backgroundGroup = DispatchGroup()
    let backgroundText = baselineText
    let backgroundFontName = font.fontName
    let backgroundStart = ContinuousClock.now
    var mainRunLoopCycles = 0
    backgroundGroup.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      autoreleasepool {
        backgroundResult.store(
          Result {
            try makeStringPlan(
              text: backgroundText, fontName: backgroundFontName, width: 858, window: 65_536)
          })
        backgroundGroup.leave()
      }
    }
    let afterKeys = (baselineText as NSString).replacingCharacters(
      in: NSRange(location: inputLocation, length: 0), with: String(repeating: "z", count: 20))
    let afterComposition = (baselineText as NSString).replacingCharacters(
      in: NSRange(location: inputLocation, length: 0),
      with: String(repeating: "z", count: 20) + "🙂")
    var inputSamples: [Duration] = []
    for _ in 0..<20 {
      let started = ContinuousClock.now
      inputView.insertText("z", replacementRange: NSRange(location: NSNotFound, length: 0))
      inputSamples.append(started.duration(to: .now))
    }
    let expectedKeySelection = NSRange(location: inputLocation + 20, length: 0)
    guard inputView.text == afterKeys, inputView.selectedRange() == expectedKeySelection
    else {
      throw NSError(domain: "line-index", code: 28, userInfo: [NSLocalizedDescriptionKey: "direct callbacks textMatch=\(inputView.text == afterKeys) utf16=\(inputView.text.utf16.count)/\(afterKeys.utf16.count) selection=\(inputView.selectedRange()) expected=\(expectedKeySelection) inputStart=\(inputLocation) displayed=\(inputView.displayedRange)"])
    }
    inputView.setMarkedText(
      "界", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    guard inputView.hasMarkedText() else { throw NSError(domain: "line-index", code: 29) }
    inputView.insertText("🙂", replacementRange: NSRange(location: NSNotFound, length: 0))
    guard !inputView.hasMarkedText(), inputView.text == afterComposition,
      inputView.selectedRange() == NSRange(location: inputLocation + 22, length: 0)
    else { throw NSError(domain: "line-index", code: 30, userInfo: [NSLocalizedDescriptionKey: "marked-text commit changed unexpected text or selection"]) }
    guard let undoManager = inputView.undoManager else { throw NSError(domain: "line-index", code: 31) }
    undoManager.removeAllActions()
    let beforeUndoText = inputView.text
    let beforeUndoSelection = inputView.selectedRange()
    undoManager.beginUndoGrouping()
    inputView.insertText("Q", replacementRange: NSRange(location: NSNotFound, length: 0))
    undoManager.endUndoGrouping()
    undoManager.undo()
    guard inputView.text == beforeUndoText, inputView.selectedRange() == beforeUndoSelection else {
      throw NSError(domain: "line-index", code: 32, userInfo: [NSLocalizedDescriptionKey: "slice undo did not restore exact text and caret"])
    }
    guard backgroundGroup.wait(timeout: .now()) == .timedOut else {
      throw NSError(domain: "line-index", code: 42, userInfo: [NSLocalizedDescriptionKey: "background index finished before input callbacks were measured"])
    }
    while backgroundGroup.wait(timeout: .now()) == .timedOut {
      _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.016))
      mainRunLoopCycles += 1
    }
    let backgroundDuration = backgroundStart.duration(to: ContinuousClock.now)
    guard let backgroundPlan = backgroundResult.load() else {
      throw NSError(
        domain: "line-index", code: 40,
        userInfo: [NSLocalizedDescriptionKey: "background index returned no result"])
    }
    let completedBackgroundPlan = try backgroundPlan.get()
    guard completedBackgroundPlan.lines.map(\.range) == plan.lines.map(\.range),
      completedBackgroundPlan.lines.map(\.height) == plan.lines.map(\.height)
    else {
      throw NSError(
        domain: "line-index", code: 41,
        userInfo: [
          NSLocalizedDescriptionKey: "background index geometry differed from foreground geometry"
        ])
    }
    print(
      "backgroundIndex=passed duration=\(backgroundDuration) mainRunLoopCycles=\(mainRunLoopCycles) geometry=exact"
    )
    let sortedInputSamples = inputSamples.sorted()
    print("directInputCallbacks=passed samples=20 p50=\(sortedInputSamples[9]) p95=\(sortedInputSamples[18]) max=\(sortedInputSamples[19]) utf16=\(inputView.text.utf16.count) markedCommit=passed undo=exact backgroundIndex=concurrent")

    print("planBytes=\(text.utf8.count) utf16=\(source.length) lines=\(plan.lines.count) height=\(plan.height) plan=\(planDuration)")
    for renderedLineCount in [28, 32, 64] {
      var samples: [Duration] = []
      for _ in 0..<20 {
        let started = ContinuousClock.now
        try view.layoutViewport(at: middleY, linesToRender: renderedLineCount)
        samples.append(started.duration(to: .now))
      }
      let sorted = samples.sorted()
      let pixels = try visibleGlyphPixelCount(view, y: middleY, height: 500)
      guard view.displayedLineCount == renderedLineCount, pixels > 0 else {
        throw NSError(domain: "line-index", code: 23, userInfo: [NSLocalizedDescriptionKey: "middle slice \(renderedLineCount) lines did not render visible pixels"])
      }
      print("middleSliceLines=\(renderedLineCount) p50=\(sorted[9]) p95=\(sorted[18]) min=\(sorted[0]) max=\(sorted[19]) glyphPixels=\(pixels)")
    }
    for (name, y) in [("start", CGFloat(0)), ("middle", plan.height / 2), ("end", max(0, plan.height - 500))] {
      scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
      scroll.reflectScrolledClipView(scroll.contentView)
      let started = ContinuousClock.now
      try view.layoutViewport(at: y)
      let layoutDuration = started.duration(to: .now)
      let actualY = scroll.contentView.bounds.origin.y
      let inViewport = view.displayedRange.lowerBound < source.length && view.displayedRange.upperBound > 0
      let firstVisibleY = view.indexedY(for: view.displayedRange.lowerBound)
      let glyphPixels = try visibleGlyphPixelCount(view, y: actualY, height: 500)
      guard inViewport, glyphPixels > 0 else {
        throw NSError(domain: "line-index", code: 12, userInfo: [NSLocalizedDescriptionKey: "\(name): rendered glyph pixels=\(glyphPixels)"])
      }
      print("target=\(name) requestedY=\(y) actualY=\(actualY) range=\(view.displayedRange) lines=\(view.displayedLineCount) firstLineY=\(firstVisibleY) layout=\(layoutDuration) glyphPixels=\(glyphPixels)")
    }
    window.close()
    let keyWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 500), styleMask: .borderless,
      backing: .buffered, defer: false)
    keyWindow.contentView = inputView
    guard keyWindow.makeFirstResponder(inputView),
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: keyWindow.windowNumber,
        context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false,
        keyCode: 0)
    else { throw NSError(domain: "line-index", code: 43) }
    let beforeEvent = inputView.text
    let eventSelection = inputView.selectedRange()
    let expectedEventText = (beforeEvent as NSString).replacingCharacters(
      in: eventSelection, with: "a")
    inputView.keyDown(with: event)
    guard inputView.text == expectedEventText else {
      throw NSError(
        domain: "line-index", code: 44,
        userInfo: [
          NSLocalizedDescriptionKey: "synthetic keyDown was not inserted by the input context"
        ])
    }
    print("syntheticKeyDown=passed inputContext=inserted")
    keyWindow.close()
  }
}
