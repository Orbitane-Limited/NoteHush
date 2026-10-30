import AppKit
import CoreText
import CryptoKit
import Foundation

final class RangeProbeLocation: NSObject, NSTextLocation {
  let offset: Int
  init(_ offset: Int) { self.offset = offset }
  func compare(_ location: any NSTextLocation) -> ComparisonResult {
    guard let other = location as? RangeProbeLocation else { return .orderedSame }
    if offset < other.offset { return .orderedAscending }
    if offset > other.offset { return .orderedDescending }
    return .orderedSame
  }
}

final class RangeProbeContentManager: NSTextContentManager {
  let source: NSAttributedString
  let chunkUnits: Int
  private(set) var emitted = 0
  init(source: NSAttributedString, chunkUnits: Int) {
    self.source = source
    self.chunkUnits = chunkUnits
    super.init()
  }
  required init?(coder: NSCoder) { nil }
  override var documentRange: NSTextRange {
    // The generated document range always uses valid UTF-16 endpoints.
    NSTextRange(location: RangeProbeLocation(0), end: RangeProbeLocation(source.length))!
  }
  override func enumerateTextElements(
    from textLocation: (any NSTextLocation)?,
    options: NSTextContentManager.EnumerationOptions,
    using block: (NSTextElement) -> Bool
  ) -> (any NSTextLocation)? {
    guard !options.contains(.reverse) else { return nil }
    let requested = (textLocation as? RangeProbeLocation)?.offset ?? 0
    let headerEnd = min(16, source.length)
    var ranges: [(Int, Int)] = [(0, headerEnd)]
    var start = headerEnd
    while start < source.length {
      let end = min(source.length, start + chunkUnits)
      ranges.append((start, end))
      start = end
    }
    for (start, end) in ranges where end > requested {
      let value = source.attributedSubstring(from: NSRange(location: start, length: end - start))
      let element = NSTextParagraph(attributedString: value)
      element.textContentManager = self
      // Each element range uses endpoints in the generated document.
      element.elementRange = NSTextRange(
        location: RangeProbeLocation(start), end: RangeProbeLocation(end))!
      emitted += 1
      if !block(element) { return RangeProbeLocation(end) }
    }
    return RangeProbeLocation(source.length)
  }
  override func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (
    any NSTextLocation
  )? {
    guard let value = location as? RangeProbeLocation else { return nil }
    let next = value.offset + offset
    guard (0...source.length).contains(next) else { return nil }
    return RangeProbeLocation(next)
  }
  override func offset(from: any NSTextLocation, to: any NSTextLocation) -> Int {
    guard let start = from as? RangeProbeLocation, let end = to as? RangeProbeLocation else {
      return NSNotFound
    }
    return end.offset - start.offset
  }
}

@MainActor
final class RangeProbeView: NSView {
  var fragments: [NSTextLayoutFragment] = []
  var renderOffsetY: CGFloat = 0
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let documentDirtyRect = dirtyRect.offsetBy(dx: 0, dy: renderOffsetY)
    for fragment in fragments where fragment.layoutFragmentFrame.intersects(documentDirtyRect) {
      fragment.draw(
        at: CGPoint(
          x: fragment.layoutFragmentFrame.origin.x,
          y: fragment.layoutFragmentFrame.origin.y - renderOffsetY),
        in: context)
    }
  }
}

struct IndexedLine {
  let start: Int
  let end: Int
  let y: CGFloat
  let height: CGFloat
}

func makeLineIndex(_ source: NSAttributedString, width: CGFloat) throws -> [IndexedLine] {
  let headerLength = min(16, source.length)
  let typesetterChunkUnits = 64_768
  var lines: [IndexedLine] = []
  var rangeStart = 0
  var y: CGFloat = 0
  while rangeStart < source.length {
    let rangeEnd =
      rangeStart == 0 ? headerLength : min(source.length, rangeStart + typesetterChunkUnits)
    let attributed = source.attributedSubstring(
      from: NSRange(location: rangeStart, length: rangeEnd - rangeStart))
    let typesetter = CTTypesetterCreateWithAttributedString(attributed as CFAttributedString)
    var lineStart = 0
    while lineStart < attributed.length {
      let count = CTTypesetterSuggestLineBreak(typesetter, lineStart, width)
      guard count > 0 else { throw NSError(domain: "probe", code: 1) }
      let line = CTTypesetterCreateLine(typesetter, CFRange(location: lineStart, length: count))
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
      let height = max(1, ascent + descent + leading)
      lines.append(
        IndexedLine(
          start: rangeStart + lineStart, end: rangeStart + lineStart + count, y: y, height: height))
      y += height
      lineStart += count
    }
    rangeStart = rangeEnd
  }
  return lines
}

func line(atY y: CGFloat, in lines: [IndexedLine]) -> Int {
  var low = 0
  var high = lines.count
  while low < high {
    let middle = (low + high) / 2
    if lines[middle].y + lines[middle].height < y { low = middle + 1 } else { high = middle }
  }
  return min(low, max(0, lines.count - 1))
}

@MainActor
func run(bytes: Int, chunkUnits: Int, scrollY: CGFloat) throws {
  let header = "123456789012345\n"
  let unit = "خط📝"
  let text = header + String(repeating: unit, count: (bytes - header.utf8.count) / unit.utf8.count)
  guard text.utf8.count == bytes else { throw NSError(domain: "probe", code: 2) }
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
    .paragraphStyle: style,
  ]
  let attributed = NSAttributedString(string: text, attributes: attrs)
  let indexClock = ContinuousClock.now
  let lines = try makeLineIndex(attributed, width: 858)
  let indexElapsed = indexClock.duration(to: .now)
  let prefetchY = max(0, scrollY - 2_800)
  let firstVisibleLine = line(atY: prefetchY, in: lines)
  let targetOffset = lines[firstVisibleLine].start
  let targetEnd = lines[min(lines.count - 1, firstVisibleLine + 180)].end
  let manager = RangeProbeContentManager(source: attributed, chunkUnits: chunkUnits)
  let layout = NSTextLayoutManager()
  manager.addTextLayoutManager(layout)
  manager.primaryTextLayoutManager = layout
  let container = NSTextContainer(size: NSSize(width: 858, height: CGFloat.greatestFiniteMagnitude))
  container.widthTracksTextView = true
  layout.textContainer = container
  guard
    let startLocation = manager.location(manager.documentRange.location, offsetBy: targetOffset),
    let endLocation = manager.location(manager.documentRange.location, offsetBy: targetEnd),
    let targetRange = NSTextRange(location: startLocation, end: endLocation)
  else {
    throw NSError(domain: "probe", code: 3)
  }
  let layoutClock = ContinuousClock.now
  layout.ensureLayout(for: targetRange)
  var fragments: [NSTextLayoutFragment] = []
  var covered = targetOffset
  _ = layout.enumerateTextLayoutFragments(from: startLocation, options: [.ensuresLayout]) {
    fragment in
    fragments.append(fragment)
    guard let elementRange = fragment.textElement?.elementRange,
      let elementStart = elementRange.location as? RangeProbeLocation
    else { return false }
    for line in fragment.textLineFragments {
      let lineStart = elementStart.offset + line.characterRange.location
      if lineStart <= covered && lineStart + line.characterRange.length > covered {
        covered = lineStart + line.characterRange.length
      }
    }
    return covered < targetEnd
  }
  let layoutElapsed = layoutClock.duration(to: .now)
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 868, pixelsHigh: 500, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
  else {
    throw NSError(domain: "probe", code: 4)
  }
  let context = NSGraphicsContext(bitmapImageRep: bitmap)
  let rangeView = RangeProbeView(frame: NSRect(x: 0, y: 0, width: 868, height: 500))
  rangeView.fragments = fragments
  rangeView.renderOffsetY = scrollY
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context?.cgContext.setFillColor(NSColor.white.cgColor)
  context?.cgContext.fill(CGRect(x: 0, y: 0, width: 868, height: 500))
  let drawClock = ContinuousClock.now
  rangeView.draw(rangeView.bounds)
  let drawElapsed = drawClock.duration(to: .now)
  NSGraphicsContext.restoreGraphicsState()
  try bitmap.representation(using: .png, properties: [:])?.write(
    to: URL(fileURLWithPath: "/private/tmp/NoteHushRangeMappedViewport.png"))
  let bytesData =
    bitmap.bitmapData.map { Data(bytes: $0, count: bitmap.bytesPerRow * bitmap.pixelsHigh) }
    ?? Data()
  let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  let bitmapDigest = SHA256.hash(data: bytesData).map { String(format: "%02x", $0) }.joined()
  let nonWhitePixels = stride(from: 0, to: bytesData.count, by: 4).reduce(into: 0) {
    count, offset in
    if offset + 2 < bytesData.count
      && (bytesData[offset] < 240 || bytesData[offset + 1] < 240 || bytesData[offset + 2] < 240)
    {
      count += 1
    }
  }
  let firstFragmentY = fragments.first?.layoutFragmentFrame.origin.y ?? -1
  let lastFragmentY = fragments.last?.layoutFragmentFrame.origin.y ?? -1
  let visibleRect = CGRect(x: 0, y: scrollY, width: 868, height: 500)
  let visibleFragmentCount = fragments.filter { $0.layoutFragmentFrame.intersects(visibleRect) }
    .count
  let fragmentRanges = fragments.compactMap { fragment -> [Int]? in
    guard let range = fragment.textElement?.elementRange,
      let start = range.location as? RangeProbeLocation,
      let end = range.endLocation as? RangeProbeLocation
    else { return nil }
    return [start.offset, end.offset, fragment.textLineFragments.count]
  }
  try bitmap.representation(using: .png, properties: [:])?.write(
    to: URL(fileURLWithPath: "/private/tmp/NoteHushRangeMappedViewport.png"))
  let result: [String: Any] = [
    "inputBytes": text.utf8.count,
    "sourceUTF16": text.utf16.count,
    "textDigest": digest,
    "width": 858,
    "chunkUnits": chunkUnits,
    "lineCount": lines.count,
    "estimatedContentHeight": lines.last.map { $0.y + $0.height } ?? 0,
    "indexElapsed": String(describing: indexElapsed),
    "requestedScrollY": Double(scrollY),
    "mappedLine": firstVisibleLine,
    "mappedOffsetUTF16": targetOffset,
    "mappedLineY": Double(lines[firstVisibleLine].y),
    "prefetchY": Double(prefetchY),
    "layoutElapsed": String(describing: layoutElapsed),
    "drawElapsed": String(describing: drawElapsed),
    "fragments": fragments.count,
    "visibleFragments": visibleFragmentCount,
    "nonWhitePixels": nonWhitePixels,
    "emittedElements": manager.emitted,
    "coveredThroughUTF16": covered,
    "targetEndUTF16": targetEnd,
    "firstFragmentY": firstFragmentY,
    "lastFragmentY": lastFragmentY,
    "fragmentRanges": fragmentRanges,
    "usageBounds": [
      layout.usageBoundsForTextContainer.origin.x, layout.usageBoundsForTextContainer.origin.y,
      layout.usageBoundsForTextContainer.width, layout.usageBoundsForTextContainer.height,
    ],
    "bitmapDigest": bitmapDigest,
  ]
  let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
  print(String(decoding: data, as: UTF8.self))
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let args = Array(CommandLine.arguments.dropFirst())
let bytes = Int(args.first ?? "10485760") ?? 10_485_760
let chunk = Int(args.dropFirst().first ?? "4048") ?? 4_048
let scrollY = CGFloat(Double(args.dropFirst(2).first ?? "500000") ?? 500_000)
try await MainActor.run { try run(bytes: bytes, chunkUnits: chunk, scrollY: scrollY) }
