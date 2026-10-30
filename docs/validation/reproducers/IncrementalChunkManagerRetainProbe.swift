import AppKit
import CoreText
import Foundation

struct InputIndexedLine: Sendable {
  let start: Int
  let end: Int
  let y: CGFloat
  let height: CGFloat
}

func makeInputLineIndex(text: String, width: CGFloat, fontName: String) throws
  -> [InputIndexedLine]
{
  let font = CTFontCreateWithName(fontName as CFString, 14, nil)
  let attributes = [kCTFontAttributeName: font] as CFDictionary
  guard let source = CFAttributedStringCreate(nil, text as CFString, attributes) else {
    throw NSError(domain: "input-probe", code: 20)
  }
  let sourceLength = CFAttributedStringGetLength(source)
  let chunkUnits = 64_768
  var lines: [InputIndexedLine] = []
  var start = 0
  var y: CGFloat = 0
  while start < sourceLength {
    let end = min(sourceLength, start + chunkUnits)
    let range = CFRange(location: start, length: end - start)
    guard let attributed = CFAttributedStringCreateWithSubstring(nil, source, range) else {
      throw NSError(domain: "input-probe", code: 21)
    }
    let typesetter = CTTypesetterCreateWithAttributedString(attributed)
    var local = 0
    while local < range.length {
      let count = CTTypesetterSuggestLineBreak(typesetter, local, width)
      guard count > 0 else { throw NSError(domain: "input-probe", code: 22) }
      let line = CTTypesetterCreateLine(typesetter, CFRange(location: local, length: count))
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
      let height = max(1, ascent + descent + leading)
      lines.append(
        InputIndexedLine(start: start + local, end: start + local + count, y: y, height: height))
      y += height
      local += count
    }
    start = end
  }
  return lines
}

final class InputBoundedTextShaper {
  func lineEnds(in source: NSAttributedString) -> [Int] {
    let typesetter = CTTypesetterCreateWithAttributedString(source as CFAttributedString)
    var result: [Int] = []
    var offset = 0
    while offset < source.length {
      let count = CTTypesetterSuggestLineBreak(typesetter, offset, 858)
      guard count > 0 else { return [] }
      offset += count
      result.append(offset)
    }
    return result
  }
}

final class InputProbeLocation: NSObject, NSTextLocation {
  let offset: Int

  init(_ offset: Int) { self.offset = offset }

  func compare(_ other: any NSTextLocation) -> ComparisonResult {
    guard let other = other as? InputProbeLocation else { return .orderedSame }
    if offset < other.offset { return .orderedAscending }
    if offset > other.offset { return .orderedDescending }
    return .orderedSame
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? InputProbeLocation else { return false }
    return offset == other.offset
  }

  override var hash: Int { offset }
}

final class ChunkedInputDocument: NSTextContentManager {
  private(set) var pieces: [NSAttributedString]
  private(set) var chunks: [NSRange]
  private(set) var utf16Count: Int
  private let chunkUnits: Int
  private let shaper: InputBoundedTextShaper
  private(set) var emittedCount = 0
  private var lastEdit: (start: Int, oldEnd: Int, newEnd: Int)?

  init(source: NSAttributedString, chunkUnits: Int) {
    self.chunkUnits = chunkUnits
    let shaper = InputBoundedTextShaper()
    self.shaper = shaper
    pieces = Self.split(source, maximum: chunkUnits, shaper: shaper)
    chunks = []
    utf16Count = source.length
    super.init()
    rebuildRanges()
  }

  required init?(coder: NSCoder) { nil }

  var source: NSAttributedString {
    let joined = NSMutableAttributedString()
    for piece in pieces { joined.append(piece) }
    return joined
  }

  func text(in range: NSRange) -> String? {
    attributedSubstring(in: range)?.string
  }

  func attributedSubstring(in range: NSRange) -> NSAttributedString? {
    guard range.location >= 0, range.length >= 0,
      range.location <= utf16Count, range.length <= utf16Count - range.location
    else { return nil }
    let result = NSMutableAttributedString()
    let end = NSMaxRange(range)
    for (index, chunk) in chunks.enumerated() {
      let overlapStart = max(range.location, chunk.location)
      let overlapEnd = min(end, NSMaxRange(chunk))
      guard overlapEnd > overlapStart else { continue }
      let local = NSRange(
        location: overlapStart - chunk.location, length: overlapEnd - overlapStart)
      result.append(pieces[index].attributedSubstring(from: local))
    }
    return result
  }

  private static func split(
    _ attributed: NSAttributedString, maximum: Int, shaper: InputBoundedTextShaper
  ) -> [NSAttributedString] {
    if attributed.length > maximum {
      let lineEnds = shaper.lineEnds(in: attributed)
      if !lineEnds.isEmpty {
        var result: [NSAttributedString] = []
        var start = 0
        while start < attributed.length {
          let limit = min(attributed.length, start + maximum)
          let end = lineEnds.last(where: { $0 > start && $0 <= limit })
            ?? lineEnds.first(where: { $0 > limit }) ?? attributed.length
          guard end > start else { break }
          result.append(
            attributed.attributedSubstring(from: NSRange(location: start, length: end - start)))
          start = end
        }
        if start == attributed.length { return result }
      }
    }
    let string = attributed.string as NSString
    var result: [NSAttributedString] = []
    var start = 0
    while start < string.length {
      var end = min(string.length, start + maximum)
      if end < string.length {
        let separator = string.rangeOfCharacter(
          from: .newlines, options: .literal, range: NSRange(location: start, length: end - start))
        if separator.location != NSNotFound {
          end = NSMaxRange(separator)
          if string.character(at: separator.location) == 0x0d,
            end < string.length, string.character(at: end) == 0x0a
          {
            end += 1
          }
        }
      }
      if end < string.length {
        let grapheme = string.rangeOfComposedCharacterSequence(at: end)
        if grapheme.location < end { end = grapheme.location }
      }
      if end <= start { end = min(string.length, start + 1) }
      result.append(
        attributed.attributedSubstring(from: NSRange(location: start, length: end - start)))
      start = end
    }
    return result
  }

  private func rebuildRanges() {
    var cursor = 0
    chunks = pieces.map { piece in
      defer { cursor += piece.length }
      return NSRange(location: cursor, length: piece.length)
    }
    utf16Count = cursor
  }

  @preconcurrency override func replaceContents(
    in range: NSTextRange, with textElements: [NSTextElement]?
  ) {
    guard let start = range.location as? InputProbeLocation,
      let end = range.endLocation as? InputProbeLocation,
      start.offset >= 0, end.offset >= start.offset, end.offset <= utf16Count
    else { return }
    let replacement = (textElements ?? []).compactMap {
      ($0 as? NSTextParagraph)?.attributedString
    }
    .flatMap { Self.split($0, maximum: chunkUnits, shaper: shaper) }
    if chunks.isEmpty {
      guard start.offset == 0, end.offset == 0 else { return }
      pieces.append(contentsOf: replacement)
    } else {
      guard let firstIndex = chunks.firstIndex(where: { $0.location == start.offset }),
        let lastIndex = chunks.firstIndex(where: { NSMaxRange($0) == end.offset }),
        lastIndex >= firstIndex
      else { return }
      pieces.replaceSubrange(firstIndex...lastIndex, with: replacement)
    }
    let insertedLength = replacement.reduce(0) { $0 + $1.length }
    lastEdit = (start.offset, end.offset, start.offset + insertedLength)
    rebuildRanges()
  }

  override func adjustedRange(
    from textRange: NSTextRange, forEditingTextSelection: Bool
  ) -> NSTextRange? {
    guard let edit = lastEdit,
      let start = textRange.location as? InputProbeLocation,
      let end = textRange.endLocation as? InputProbeLocation,
      end.offset > edit.start
    else { return nil }
    let delta = edit.newEnd - edit.oldEnd
    func adjusted(_ offset: Int) -> Int {
      if offset < edit.start { return offset }
      if offset >= edit.oldEnd { return offset + delta }
      return edit.newEnd
    }
    let newStart = adjusted(start.offset)
    let newEnd = max(newStart, adjusted(end.offset))
    guard newStart != start.offset || newEnd != end.offset else { return nil }
    return NSTextRange(
      location: InputProbeLocation(newStart), end: InputProbeLocation(newEnd))
  }

  override var documentRange: NSTextRange {
    // Both locations are generated from the immutable UTF-16 source bounds.
    NSTextRange(location: InputProbeLocation(0), end: InputProbeLocation(utf16Count))!
  }

  override func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (
    any NSTextLocation
  )? {
    guard let location = location as? InputProbeLocation else { return nil }
    let next = location.offset + offset
    guard (0...utf16Count).contains(next) else { return nil }
    return InputProbeLocation(next)
  }

  override func offset(from: any NSTextLocation, to: any NSTextLocation) -> Int {
    guard let start = from as? InputProbeLocation, let end = to as? InputProbeLocation else {
      return NSNotFound
    }
    return end.offset - start.offset
  }

  override func enumerateTextElements(
    from location: (any NSTextLocation)?, options: EnumerationOptions,
    using block: (NSTextElement) -> Bool
  ) -> (any NSTextLocation)? {
    let reverse = options.contains(.reverse)
    let offset = (location as? InputProbeLocation)?.offset ?? (reverse ? utf16Count : 0)
    let indices = reverse ? Array(pieces.indices.reversed()) : Array(pieces.indices)
    var last = InputProbeLocation(offset)
    for index in indices {
      let range = chunks[index]
      let end = NSMaxRange(range)
      guard reverse ? range.location < offset : end > offset else { continue }
      let paragraph = NSTextParagraph(attributedString: pieces[index])
      paragraph.textContentManager = self
      paragraph.elementRange = NSTextRange(
        location: InputProbeLocation(range.location), end: InputProbeLocation(end))!
      emittedCount += 1
      last = InputProbeLocation(reverse ? range.location : end)
      if !block(paragraph) { return last }
    }
    return last
  }
}

@MainActor
final class ChunkedInputSurface: NSView, @preconcurrency NSTextInputClient {
  private let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  private let chunkUnits: Int
  var text: String { document.source.string }
  var chunkRanges: [NSRange] { document.chunks }
  private(set) var selection = NSRange(location: 0, length: 0)
  private(set) var marked = NSRange(location: NSNotFound, length: 0)
  private var document: ChunkedInputDocument
  private(set) var chunkCount = 0
  private var layout = NSTextLayoutManager()
  private var fragments: [NSTextLayoutFragment] = []
  private var context: NSTextInputContext?
  private var viewportLines: [InputIndexedLine] = []
  private(set) var lastViewportOffset = 0
  private(set) var lastViewportEnd = 0

  override var isFlipped: Bool { true }

  init(text: String, chunkUnits: Int) {
    self.chunkUnits = chunkUnits
    document = ChunkedInputDocument(
      source: Self.attributed(text, font: font), chunkUnits: chunkUnits)
    super.init(frame: NSRect(x: 0, y: 0, width: 868, height: 500))
    rebuildLayout()
  }

  required init?(coder: NSCoder) { nil }
  override var acceptsFirstResponder: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil { context = NSTextInputContext(client: self) }
  }

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { context?.activate() }
    return accepted
  }

  override func resignFirstResponder() -> Bool {
    unmarkText()
    context?.deactivate()
    return super.resignFirstResponder()
  }

  private static func attributed(_ text: String, font: NSFont) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.baseWritingDirection = .natural
    return NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
  }

  private func rebuildLayout(for requestedRange: NSTextRange? = nil) {
    chunkCount = document.chunks.count
    fragments.removeAll()
    guard let range = requestedRange ?? document.chunks.first.flatMap(textRange) else {
      needsDisplay = true
      return
    }
    if layout.textContainer == nil {
      document.addTextLayoutManager(layout)
      document.primaryTextLayoutManager = layout
      let container = NSTextContainer(
        size: NSSize(width: max(1, bounds.width - 10), height: CGFloat.greatestFiniteMagnitude))
      container.widthTracksTextView = false
      layout.textContainer = container
    }
    layout.ensureLayout(for: range)
    _ = layout.enumerateTextLayoutFragments(from: range.location, options: []) {
      [weak self] fragment in
      self?.fragments.append(fragment)
      return false
    }
    needsDisplay = true
  }

  func installViewportIndex(_ lines: [InputIndexedLine]) {
    viewportLines = lines
    let height = lines.last.map { $0.y + $0.height } ?? bounds.height
    setFrameSize(NSSize(width: bounds.width, height: max(bounds.height, height)))
  }

  func layoutViewport(y: CGFloat, prefetch: Int = 180) {
    guard !viewportLines.isEmpty else { return }
    let targetY = max(0, y - 2_800)
    var low = 0
    var high = viewportLines.count
    while low < high {
      let middle = (low + high) / 2
      if viewportLines[middle].y + viewportLines[middle].height < targetY {
        low = middle + 1
      } else {
        high = middle
      }
    }
    let first = min(low, viewportLines.count - 1)
    let last = min(viewportLines.count - 1, first + prefetch)
    let start = viewportLines[first].start
    let end = viewportLines[last].end
    guard let range = textRange(NSRange(location: start, length: end - start)) else { return }
    layout.ensureLayout(for: range)
    fragments.removeAll(keepingCapacity: true)
    var covered = start
    _ = layout.enumerateTextLayoutFragments(from: range.location, options: [.ensuresLayout]) {
      fragment in
      fragments.append(fragment)
      guard let elementRange = fragment.textElement?.elementRange,
        let elementStart = elementRange.location as? InputProbeLocation
      else { return false }
      for line in fragment.textLineFragments {
        let lineStart = elementStart.offset + line.characterRange.location
        if lineStart <= covered && lineStart + line.characterRange.length > covered {
          covered = lineStart + line.characterRange.length
        }
      }
      return covered < end
    }
    lastViewportOffset = start
    lastViewportEnd = covered
    needsDisplay = true
  }

  func visibleFragmentCount(in rect: CGRect) -> Int {
    fragments.filter { $0.layoutFragmentFrame.intersects(rect) }.count
  }

  func renderProbe(y: CGFloat, height: Int = 500) throws -> Int {
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(bounds.width), pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      )
    else { throw NSError(domain: "input-probe", code: 23) }
    cacheDisplay(
      in: NSRect(x: 0, y: y, width: bounds.width, height: CGFloat(height)), to: bitmap)
    try bitmap.representation(using: .png, properties: [:])?.write(
      to: URL(fileURLWithPath: "/private/tmp/NoteHushInputViewport-\(Int(y)).png"))
    guard let bytes = bitmap.bitmapData else { return 0 }
    let byteCount = bitmap.bytesPerRow * height
    return stride(from: 0, to: byteCount, by: 4).reduce(into: 0) { count, offset in
      if offset + 2 < byteCount,
        bytes[offset] < 240 || bytes[offset + 1] < 240 || bytes[offset + 2] < 240
      {
        count += 1
      }
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let documentDirtyRect = dirtyRect
    context.setFillColor(NSColor.textBackgroundColor.cgColor)
    context.fill(documentDirtyRect)
    if selection.length > 0, let range = textRange(selection) {
      layout.enumerateTextSegments(in: range, type: .selection, options: []) { _, rect, _, _ in
        context.setFillColor(NSColor.selectedTextBackgroundColor.cgColor)
        context.fill(rect)
        return true
      }
    }
    for fragment in fragments where fragment.layoutFragmentFrame.intersects(documentDirtyRect) {
      fragment.draw(
        at: CGPoint(
          x: fragment.layoutFragmentFrame.origin.x,
          y: fragment.layoutFragmentFrame.origin.y),
        in: context)
    }
    if marked.location != NSNotFound, let range = textRange(marked) {
      layout.enumerateTextSegments(in: range, type: .standard, options: []) { _, rect, _, _ in
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: rect.minX, y: rect.maxY - 1))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 1))
        context.strokePath()
        return true
      }
    }
  }

  override func keyDown(with event: NSEvent) {
    if context?.handleEvent(event) != true { super.keyDown(with: event) }
  }

  func handle(_ event: NSEvent) -> Bool {
    context?.handleEvent(event) ?? false
  }

  func select(_ range: NSRange) {
    guard range.location >= 0, range.length >= 0,
      range.location <= document.utf16Count,
      range.length <= document.utf16Count - range.location
    else { return }
    selection = range
  }

  private func textRange(_ range: NSRange) -> NSTextRange? {
    guard range.location != NSNotFound, range.location >= 0,
      range.location + range.length <= document.utf16Count,
      let start = document.location(document.documentRange.location, offsetBy: range.location),
      let end = document.location(
        document.documentRange.location, offsetBy: range.location + range.length)
    else { return nil }
    return NSTextRange(location: start, end: end)
  }

  private func replace(_ range: NSRange, with replacement: String, selected: NSRange) {
    guard range.location != NSNotFound, range.location >= 0,
      range.location + range.length <= document.utf16Count
    else { return }
    let firstIndex =
      document.chunks.firstIndex(where: { NSMaxRange($0) > range.location })
      ?? (range.location == document.utf16Count ? document.chunks.indices.last : nil)
    if !document.chunks.isEmpty, firstIndex == nil { return }
    let end = range.location + range.length
    let lastIndex =
      document.chunks.isEmpty
      ? nil
      : (range.length == 0
        ? firstIndex
        : (document.chunks.lastIndex(where: { $0.location < end }) ?? firstIndex))
    if let firstIndex, let lastIndex, lastIndex < document.chunks.count {
      guard lastIndex >= firstIndex else { return }
    }
    let replacedChunkRange: NSRange
    if let firstIndex, let lastIndex {
      let firstChunk = document.chunks[firstIndex]
      let lastChunk = document.chunks[lastIndex]
      replacedChunkRange = NSRange(
        location: firstChunk.location, length: NSMaxRange(lastChunk) - firstChunk.location)
    } else {
      guard document.chunks.isEmpty, range.location == 0, range.length == 0 else { return }
      replacedChunkRange = NSRange(location: 0, length: 0)
    }
    guard let oldChunkText = document.text(in: replacedChunkRange) else { return }
    let oldChunk = oldChunkText as NSString
    let localRange = NSRange(
      location: range.location - replacedChunkRange.location, length: range.length)
    let updatedChunk = oldChunk.replacingCharacters(in: localRange, with: replacement)
    let attributed = Self.attributed(updatedChunk, font: font)
    let element = NSTextParagraph(attributedString: attributed)
    element.textContentManager = document
    let oldTextRange = NSTextRange(
      location: InputProbeLocation(replacedChunkRange.location),
      end: InputProbeLocation(NSMaxRange(replacedChunkRange)))!
    let newTextRange = NSTextRange(
      location: InputProbeLocation(replacedChunkRange.location),
      end: InputProbeLocation(replacedChunkRange.location + updatedChunk.utf16.count))!
    element.elementRange = newTextRange
    document.performEditingTransaction {
      document.replaceContents(in: oldTextRange, with: [element])
      document.recordEditAction(in: oldTextRange, newTextRange: newTextRange)
    }
    selection = selected
    fragments.removeAll()
    rebuildLayout(for: newTextRange)
    needsDisplay = true
    context?.invalidateCharacterCoordinates()
  }

  func insertText(_ string: Any, replacementRange: NSRange) {
    let value = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    let range =
      replacementRange.location == NSNotFound
      ? (marked.location == NSNotFound ? selection : marked) : replacementRange
    replace(
      range, with: value,
      selected: NSRange(location: range.location + value.utf16.count, length: 0))
    marked = NSRange(location: NSNotFound, length: 0)
  }

  func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    let value = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    let range =
      replacementRange.location == NSNotFound
      ? (marked.location == NSNotFound ? selection : marked) : replacementRange
    replace(
      range, with: value,
      selected: NSRange(
        location: range.location + selectedRange.location, length: selectedRange.length))
    marked = NSRange(location: range.location, length: value.utf16.count)
  }

  func unmarkText() { marked = NSRange(location: NSNotFound, length: 0) }
  func selectedRange() -> NSRange { selection }
  func markedRange() -> NSRange { marked }
  func hasMarkedText() -> Bool { marked.location != NSNotFound }
  func validAttributesForMarkedText() -> [NSAttributedString.Key] { [.underlineStyle] }

  func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?)
    -> NSAttributedString?
  {
    guard range.location >= 0, range.location + range.length <= document.utf16Count else {
      return nil
    }
    actualRange?.pointee = range
    return document.attributedSubstring(in: range)
  }

  func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
    guard let window, let textRange = textRange(range) else { return .zero }
    var result = CGRect.zero
    layout.enumerateTextSegments(in: textRange, type: .standard, options: []) {
      segment, rect, _, _ in
      if let segment, let start = segment.location as? InputProbeLocation,
        let end = segment.endLocation as? InputProbeLocation
      {
        actualRange?.pointee = NSRange(location: start.offset, length: end.offset - start.offset)
      }
      result = rect
      return false
    }
    return window.convertToScreen(convert(result, to: nil))
  }

  func characterIndex(for point: NSPoint) -> Int {
    guard let window else { return NSNotFound }
    let local = convert(window.convertPoint(fromScreen: point), from: nil)
    guard let fragment = layout.textLayoutFragment(for: local),
      let element = fragment.textElement?.elementRange?.location as? InputProbeLocation,
      let line = fragment.textLineFragments.first(where: { $0.typographicBounds.contains(local) })
    else { return NSNotFound }
    return element.offset + line.characterRange.location
  }

  override func doCommand(by selector: Selector) {}
}

@main
@MainActor
enum ChunkedTextInputClientProbe {
  static func main() async throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let text = String(repeating: "خط📝", count: 4_000)
    let surface = ChunkedInputSurface(text: text, chunkUnits: 4_048)
    let appended = "界"
    surface.setMarkedText(
      appended, selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: 0, length: 0))
    guard surface.text == appended + text, surface.hasMarkedText(),
      surface.selectedRange() == NSRange(location: 1, length: 0)
    else { throw NSError(domain: "input-probe", code: 1) }
    surface.insertText("🙂", replacementRange: NSRange(location: NSNotFound, length: 0))
    guard surface.text == "🙂" + text, !surface.hasMarkedText(),
      surface.selectedRange() == NSRange(location: 2, length: 0)
    else { throw NSError(domain: "input-probe", code: 2) }

    let mutableStyle = NSMutableParagraphStyle()
    mutableStyle.baseWritingDirection = .natural
    let largeHeader = "123456789012345\n"
    let largeText = largeHeader + String(repeating: "خط📝", count: (10_485_760 - 16) / 8)
    guard largeText.utf8.count == 10_485_760 else {
      throw NSError(domain: "input-probe", code: 6)
    }
    let mutableSource = NSAttributedString(
      string: largeText,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
        .paragraphStyle: mutableStyle,
      ])
    let mutableDocument = ChunkedInputDocument(source: mutableSource, chunkUnits: 4_048)
    let mutableLayout = NSTextLayoutManager()
    mutableDocument.addTextLayoutManager(mutableLayout)
    mutableDocument.primaryTextLayoutManager = mutableLayout
    mutableLayout.textContainer = NSTextContainer(size: NSSize(width: 800, height: 10_000))
    let editedRange = mutableDocument.chunks[0]
    let oldVisibleRange = NSTextRange(
      location: InputProbeLocation(editedRange.location),
      end: InputProbeLocation(NSMaxRange(editedRange)))!
    mutableLayout.ensureLayout(for: oldVisibleRange)
    let oldRange = NSTextRange(
      location: InputProbeLocation(editedRange.location),
      end: InputProbeLocation(NSMaxRange(editedRange)))!
    let replacementText = "EDIT"
    let replacement = NSTextParagraph(
      attributedString: NSAttributedString(
        string: replacementText,
        attributes: [
          .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
          .paragraphStyle: mutableStyle,
        ]))
    replacement.textContentManager = mutableDocument
    let newRange = NSTextRange(
      location: InputProbeLocation(editedRange.location),
      end: InputProbeLocation(editedRange.location + replacementText.utf16.count))!
    replacement.elementRange = newRange
    let editStart = ProcessInfo.processInfo.systemUptime
    mutableDocument.performEditingTransaction {
      mutableDocument.replaceContents(in: oldRange, with: [replacement])
      mutableDocument.recordEditAction(in: oldRange, newTextRange: newRange)
    }
    mutableLayout.ensureLayout(for: newRange)
    let editMilliseconds = (ProcessInfo.processInfo.systemUptime - editStart) * 1_000
    let expectedText = (largeText as NSString).replacingCharacters(
      in: editedRange, with: replacementText)
    guard mutableDocument.source.string == expectedText,
      (mutableDocument.documentRange.endLocation as? InputProbeLocation)?.offset
        == expectedText.utf16.count
    else { throw NSError(domain: "input-probe", code: 4) }
    let firstRange = NSTextRange(
      location: InputProbeLocation(0), end: InputProbeLocation(replacementText.utf16.count))!
    mutableLayout.ensureLayout(for: firstRange)
    let firstElements = mutableDocument.textElements(for: firstRange)
    let laidOutText = firstElements.compactMap { ($0 as? NSTextParagraph)?.attributedString.string }
      .joined()
    let expectedFirstChunk =
      mutableDocument.chunks.first.map {
        mutableDocument.source.attributedSubstring(from: $0).string
      } ?? ""
    guard laidOutText == expectedFirstChunk else {
      fputs(
        "editCheck=failed sourcePrefix=\(mutableDocument.source.string.prefix(12)) elements=\(firstElements.count) textPrefix=\(laidOutText.prefix(12))\\n",
        stderr)
      throw NSError(domain: "input-probe", code: 5)
    }

    let inputStart = ProcessInfo.processInfo.systemUptime
    let largeSurface = ChunkedInputSurface(text: largeText, chunkUnits: 4_048)
    let inputInitMilliseconds = (ProcessInfo.processInfo.systemUptime - inputStart) * 1_000
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 868, height: 500))
    scrollView.hasVerticalScroller = true
    scrollView.documentView = largeSurface
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 868, height: 500),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = scrollView
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    let isKeyWindow = window.isKeyWindow
    let becameFirstResponder = window.makeFirstResponder(largeSurface)
    guard
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false,
        keyCode: 6)
    else {
      window.close()
      fputs(
        "eventSetup=failed keyWindow=\(isKeyWindow) firstResponder=\(becameFirstResponder)\\n",
        stderr)
      throw NSError(domain: "input-probe", code: 3)
    }
    let keyStart = ProcessInfo.processInfo.systemUptime
    window.sendEvent(event)
    let keyMilliseconds = (ProcessInfo.processInfo.systemUptime - keyStart) * 1_000
    guard largeSurface.text == "z" + largeText else {
      window.close()
      fputs(
        "eventDispatch=failed keyWindow=\(isKeyWindow) firstResponder=\(becameFirstResponder)\\n",
        stderr)
      throw NSError(domain: "input-probe", code: 3)
    }
    var keySamples: [Double] = []
    for _ in 0..<20 {
      guard
        let repeated = NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false,
          keyCode: 0)
      else { throw NSError(domain: "input-probe", code: 14) }
      let start = ProcessInfo.processInfo.systemUptime
      window.sendEvent(repeated)
      keySamples.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
    }
    let sortedKeySamples = keySamples.sorted()
    guard largeSurface.selectedRange() == NSRange(location: 21, length: 0),
      largeSurface.text == "z" + String(repeating: "a", count: 20) + largeText
    else { throw NSError(domain: "input-probe", code: 15) }
    let keyMedian = (sortedKeySamples[9] + sortedKeySamples[10]) / 2
    let keyP95 = sortedKeySamples[18]
    let markedStart = ProcessInfo.processInfo.systemUptime
    largeSurface.setMarkedText(
      "界", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    let markedSetMilliseconds = (ProcessInfo.processInfo.systemUptime - markedStart) * 1_000
    guard largeSurface.hasMarkedText(),
      largeSurface.text == "z" + String(repeating: "a", count: 20) + "界" + largeText
    else {
      throw NSError(domain: "input-probe", code: 7)
    }
    let commitStart = ProcessInfo.processInfo.systemUptime
    largeSurface.insertText("🙂", replacementRange: NSRange(location: NSNotFound, length: 0))
    let commitMilliseconds = (ProcessInfo.processInfo.systemUptime - commitStart) * 1_000
    guard !largeSurface.hasMarkedText(),
      largeSurface.text == "z" + String(repeating: "a", count: 20) + "🙂" + largeText,
      largeSurface.selectedRange() == NSRange(location: 23, length: 0)
    else { throw NSError(domain: "input-probe", code: 8) }
    let beforeMiddleEdit = largeSurface.text
    let middleCandidate = beforeMiddleEdit.utf16.count / 2
    let middle = (beforeMiddleEdit as NSString)
      .rangeOfComposedCharacterSequence(at: middleCandidate).location
    largeSurface.select(NSRange(location: middle, length: 0))
    let middleEditStart = ProcessInfo.processInfo.systemUptime
    largeSurface.insertText("M", replacementRange: NSRange(location: NSNotFound, length: 0))
    let middleMilliseconds = (ProcessInfo.processInfo.systemUptime - middleEditStart) * 1_000
    let expectedMiddle = (beforeMiddleEdit as NSString)
      .replacingCharacters(in: NSRange(location: middle, length: 0), with: "M")
    guard largeSurface.text == expectedMiddle,
      largeSurface.selectedRange() == NSRange(location: middle + 1, length: 0)
    else { throw NSError(domain: "input-probe", code: 9) }
    let beforeEndEdit = largeSurface.text
    largeSurface.select(NSRange(location: beforeEndEdit.utf16.count, length: 0))
    largeSurface.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
    guard largeSurface.text == beforeEndEdit + "!" else {
      throw NSError(domain: "input-probe", code: 10)
    }
    let beforeCrossChunkEdit = largeSurface.text
    guard largeSurface.chunkRanges.count > 1 else { throw NSError(domain: "input-probe", code: 11) }
    let boundary = NSMaxRange(largeSurface.chunkRanges[0])
    let crossRange = NSRange(location: boundary - 2, length: 4)
    largeSurface.select(crossRange)
    largeSurface.insertText("R", replacementRange: NSRange(location: NSNotFound, length: 0))
    let expectedCrossChunk = (beforeCrossChunkEdit as NSString)
      .replacingCharacters(in: crossRange, with: "R")
    guard largeSurface.text == expectedCrossChunk else {
      throw NSError(domain: "input-probe", code: 12)
    }
    let emptySurface = ChunkedInputSurface(text: "", chunkUnits: 4_048)
    emptySurface.insertText("new draft", replacementRange: NSRange(location: NSNotFound, length: 0))
    guard emptySurface.text == "new draft" else { throw NSError(domain: "input-probe", code: 13) }

    let indexStart = ProcessInfo.processInfo.systemUptime
    let indexText = largeSurface.text
    let fontName = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular).fontName
    var indexHeartbeat = 0
    let heartbeat = Task { @MainActor in
      while !Task.isCancelled {
        indexHeartbeat += 1
        try? await Task.sleep(for: .milliseconds(16))
      }
    }
    let indexTask = Task.detached(priority: .userInitiated) {
      try makeInputLineIndex(text: indexText, width: 858, fontName: fontName)
    }
    let viewportIndex = try await indexTask.value
    heartbeat.cancel()
    await heartbeat.value
    let indexMilliseconds = (ProcessInfo.processInfo.systemUptime - indexStart) * 1_000
    largeSurface.installViewportIndex(viewportIndex)
    let scrollLimit = max(0, largeSurface.frame.height - scrollView.contentView.bounds.height)
    let scrollTargets = [CGFloat(0), CGFloat(500_000), scrollLimit]
    var viewportChecks: [String] = []
    for y in scrollTargets {
      scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
      scrollView.reflectScrolledClipView(scrollView.contentView)
      largeSurface.layoutViewport(y: y)
      let visible = CGRect(
        x: 0, y: y, width: largeSurface.bounds.width,
        height: scrollView.contentView.bounds.height)
      let visibleCount = largeSurface.visibleFragmentCount(in: visible)
      largeSurface.select(NSRange(location: largeSurface.lastViewportOffset, length: 0))
      let nonWhitePixels = try largeSurface.renderProbe(y: y)
      guard largeSurface.lastViewportEnd > largeSurface.lastViewportOffset,
        visibleCount > 0, nonWhitePixels > 0
      else { throw NSError(domain: "input-probe", code: 16) }
      viewportChecks.append(
        "y=\(Int(y)) offset=\(largeSurface.lastViewportOffset) covered=\(largeSurface.lastViewportEnd) visible=\(visibleCount) nonWhite=\(nonWhitePixels)"
      )
    }
    window.close()
    print(
      "inputClient=passed utf16=\(surface.text.utf16.count) markedText=passed replacement=passed textKitEdit=passed syntheticKey=passed input10MiB=passed appendAtEOF=passed crossChunkReplacement=passed emptyDraft=passed scroll10MiB=passed inputInit10MiB_ms=\(inputInitMilliseconds) firstKey10MiB_ms=\(keyMilliseconds) repeatedKeys20Median10MiB_ms=\(keyMedian) repeatedKeys20P95_10MiB_ms=\(keyP95) markedSet10MiB_ms=\(markedSetMilliseconds) imeCommit10MiB_ms=\(commitMilliseconds) middleEdit10MiB_ms=\(middleMilliseconds) modelEdit10MiB_ms=\(editMilliseconds) lineIndex10MiB_ms=\(indexMilliseconds) indexHeartbeat16ms_ticks=\(indexHeartbeat) lines=\(viewportIndex.count) viewports=[\(viewportChecks.joined(separator: ";"))] elements=\(mutableDocument.chunks.count)"
    )
  }
}
