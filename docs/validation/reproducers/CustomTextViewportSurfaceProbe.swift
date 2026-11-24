import AppKit
import CryptoKit
import Foundation

final class ViewportProbeLocation: NSObject, NSTextLocation {
  let offset: Int
  init(_ offset: Int) { self.offset = offset }
  func compare(_ location: any NSTextLocation) -> ComparisonResult {
    guard let other = location as? ViewportProbeLocation else { return .orderedSame }
    if offset < other.offset { return .orderedAscending }
    if offset > other.offset { return .orderedDescending }
    return .orderedSame
  }
}

final class ViewportProbeContentManager: NSTextContentManager {
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
    // Both locations are valid boundaries in this probe's generated source.
    NSTextRange(location: ViewportProbeLocation(0), end: ViewportProbeLocation(source.length))!
  }
  override func enumerateTextElements(
    from textLocation: (any NSTextLocation)?,
    options: NSTextContentManager.EnumerationOptions,
    using block: (NSTextElement) -> Bool
  ) -> (any NSTextLocation)? {
    guard !options.contains(.reverse) else { return nil }
    let requested = (textLocation as? ViewportProbeLocation)?.offset ?? 0
    let boundaries: [(Int, Int)]
    if chunkUnits >= source.length {
      boundaries = [(0, source.length)]
    } else {
      var values: [(Int, Int)] = [(0, min(16, source.length))]
      var start = min(16, source.length)
      while start < source.length {
        let end = min(source.length, start + chunkUnits)
        values.append((start, end))
        start = end
      }
      boundaries = values
    }
    for (start, end) in boundaries where end > requested {
      let actualStart = start
      guard actualStart < end else { continue }
      let attributed = source.attributedSubstring(
        from: NSRange(location: actualStart, length: end - actualStart))
      let element = NSTextParagraph(attributedString: attributed)
      element.textContentManager = self
      // The generated chunk endpoints are valid UTF-16 boundaries.
      element.elementRange = NSTextRange(
        location: ViewportProbeLocation(actualStart), end: ViewportProbeLocation(end))!
      emitted += 1
      if !block(element) { return ViewportProbeLocation(end) }
    }
    return ViewportProbeLocation(source.length)
  }
  override func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (
    any NSTextLocation
  )? {
    guard let value = location as? ViewportProbeLocation else { return nil }
    let next = value.offset + offset
    guard (0...source.length).contains(next) else { return nil }
    return ViewportProbeLocation(next)
  }
  override func offset(from: any NSTextLocation, to: any NSTextLocation) -> Int {
    guard let start = from as? ViewportProbeLocation, let end = to as? ViewportProbeLocation else {
      return NSNotFound
    }
    return end.offset - start.offset
  }
}

@MainActor
final class ViewportProbeView: NSView, @preconcurrency NSTextViewportLayoutControllerDelegate {
  let manager: ViewportProbeContentManager
  let layout: NSTextLayoutManager
  let controller: NSTextViewportLayoutController
  var fragments: [NSTextLayoutFragment] = []
  var renderOriginY: CGFloat = 0
  override var isFlipped: Bool { true }
  init(text: NSAttributedString, chunkUnits: Int) {
    manager = ViewportProbeContentManager(source: text, chunkUnits: chunkUnits)
    layout = NSTextLayoutManager()
    manager.addTextLayoutManager(layout)
    manager.primaryTextLayoutManager = layout
    let container = NSTextContainer(
      size: NSSize(width: 858, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    layout.textContainer = container
    controller = layout.textViewportLayoutController
    super.init(frame: NSRect(x: 0, y: 0, width: 868, height: 500))
    controller.delegate = self
  }
  required init?(coder: NSCoder) { nil }
  func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController) -> CGRect {
    bounds
  }
  func textViewportLayoutControllerWillLayout(
    _ textViewportLayoutController: NSTextViewportLayoutController
  ) { fragments.removeAll(keepingCapacity: true) }
  func textViewportLayoutController(
    _ textViewportLayoutController: NSTextViewportLayoutController,
    configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment
  ) { fragments.append(textLayoutFragment) }
  func textViewportLayoutControllerDidLayout(
    _ textViewportLayoutController: NSTextViewportLayoutController
  ) { needsDisplay = true }
  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    for fragment in fragments where fragment.layoutFragmentFrame.intersects(dirtyRect) {
      fragment.draw(
        at: CGPoint(
          x: fragment.layoutFragmentFrame.origin.x,
          y: fragment.layoutFragmentFrame.origin.y - renderOriginY), in: context)
    }
  }
  func runLayout() { controller.layoutViewport() }
}

@MainActor
func run(bytes: Int, chunkUnits: Int, scrollY: CGFloat, targetOffset: Int) throws {
  let header = "123456789012345\n"
  let unit = "خط📝"
  let text = header + String(repeating: unit, count: (bytes - header.utf8.count) / unit.utf8.count)
  guard text.utf8.count == bytes else { throw NSError(domain: "probe", code: 1) }
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
    .paragraphStyle: style,
  ]
  let attributed = NSAttributedString(string: text, attributes: attrs)
  let view = ViewportProbeView(text: attributed, chunkUnits: chunkUnits)
  view.setFrameSize(NSSize(width: 868, height: 1_200_000))
  let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 868, height: 500))
  scroll.documentView = view
  scroll.contentView.scroll(to: NSPoint(x: 0, y: scrollY))
  scroll.reflectScrolledClipView(scroll.contentView)
  let relocatedY: CGFloat = scrollY
  let clock = ContinuousClock()
  let start = clock.now
  if targetOffset >= 0 {
    let targetStart = min(targetOffset, text.utf16.count - 1)
    let targetEnd = min(text.utf16.count, targetStart + chunkUnits * 2)
    guard
      let startLocation = view.manager.location(
        view.manager.documentRange.location, offsetBy: targetStart),
      let endLocation = view.manager.location(
        view.manager.documentRange.location, offsetBy: targetEnd),
      let targetRange = NSTextRange(location: startLocation, end: endLocation)
    else {
      throw NSError(domain: "probe", code: 2)
    }
    view.layout.ensureLayout(for: targetRange)
    var coveredThrough = targetStart
    _ = view.layout.enumerateTextLayoutFragments(from: startLocation, options: [.ensuresLayout]) {
      fragment in
      view.fragments.append(fragment)
      guard let elementRange = fragment.textElement?.elementRange,
        let elementStart = elementRange.location as? ViewportProbeLocation
      else { return false }
      for line in fragment.textLineFragments {
        let lineStart = elementStart.offset + line.characterRange.location
        if lineStart <= coveredThrough && lineStart + line.characterRange.length > coveredThrough {
          coveredThrough = lineStart + line.characterRange.length
        }
      }
      return coveredThrough < targetEnd
    }
    view.renderOriginY = view.fragments.first?.layoutFragmentFrame.origin.y ?? 0
  } else {
    view.runLayout()
  }
  let elapsed = start.duration(to: clock.now)
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 868, pixelsHigh: 500, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
  else {
    throw NSError(domain: "probe", code: 3)
  }
  let drawingContext = NSGraphicsContext(bitmapImageRep: bitmap)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = drawingContext
  drawingContext?.cgContext.setFillColor(NSColor.white.cgColor)
  drawingContext?.cgContext.fill(CGRect(x: 0, y: 0, width: 868, height: 500))
  let drawStart = clock.now
  view.draw(view.bounds)
  let drawElapsed = drawStart.duration(to: clock.now)
  NSGraphicsContext.restoreGraphicsState()
  let bitmapBytes =
    bitmap.bitmapData.map { Data(bytes: $0, count: bitmap.bytesPerRow * bitmap.pixelsHigh) }
    ?? Data()
  let renderedDigest = SHA256.hash(data: bitmapBytes).map { String(format: "%02x", $0) }.joined()
  let nonWhitePixels = stride(from: 0, to: bitmapBytes.count, by: 4).reduce(into: 0) {
    count, index in
    if index + 2 < bitmapBytes.count
      && (bitmapBytes[index] < 240 || bitmapBytes[index + 1] < 240 || bitmapBytes[index + 2] < 240)
    {
      count += 1
    }
  }
  let ranges = view.fragments.compactMap { fragment -> [Int]? in
    guard let elementRange = fragment.textElement?.elementRange,
      let first = elementRange.location as? ViewportProbeLocation,
      let last = elementRange.endLocation as? ViewportProbeLocation
    else { return nil }
    return [first.offset, last.offset, fragment.textLineFragments.count]
  }
  let coveredUnits = ranges.reduce(0) { $0 + max(0, $1[1] - $1[0]) }
  let rangeSamples = ranges.count <= 6 ? ranges : Array(ranges.prefix(3)) + Array(ranges.suffix(3))
  let result: [String: Any] = [
    "requestedUTF8Bytes": bytes,
    "actualUTF8Bytes": text.utf8.count,
    "sourceUTF16": text.utf16.count,
    "chunkUTF16": chunkUnits,
    "elapsed": String(describing: elapsed),
    "drawElapsed": String(describing: drawElapsed),
    "renderedBitmapSHA256": renderedDigest,
    "nonWhitePixels": nonWhitePixels,
    "fragments": view.fragments.count,
    "emittedElements": view.manager.emitted,
    "fragmentRangeCount": ranges.count,
    "fragmentRangeSamples": rangeSamples,
    "coveredUTF16UnitsByFragments": coveredUnits,
    "firstFragmentY": view.fragments.first?.layoutFragmentFrame.origin.y ?? -1,
    "lastFragmentY": view.fragments.last?.layoutFragmentFrame.origin.y ?? -1,
    "renderOriginY": Double(view.renderOriginY),
    "bounds": [view.bounds.origin.x, view.bounds.origin.y, view.bounds.width, view.bounds.height],
    "visibleRect": [
      view.visibleRect.origin.x, view.visibleRect.origin.y, view.visibleRect.width,
      view.visibleRect.height,
    ],
    "requestedScrollY": Double(scrollY),
    "targetOffsetUTF16": targetOffset,
    "relocatedY": Double(relocatedY),
    "textDigest": SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined(),
  ]
  let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
  print(String(decoding: data, as: UTF8.self))
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let args = Array(CommandLine.arguments.dropFirst())
let bytes = Int(args.first ?? "10485760") ?? 10_485_760
let chunk = Int(args.dropFirst().first ?? "64768") ?? 64_768
let scrollY = CGFloat(Double(args.dropFirst(2).first ?? "0") ?? 0)
let targetOffset = Int(args.dropFirst(3).first ?? "-1") ?? -1
try await MainActor.run {
  try run(bytes: bytes, chunkUnits: chunk, scrollY: scrollY, targetOffset: targetOffset)
}
