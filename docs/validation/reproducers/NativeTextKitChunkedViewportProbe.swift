import AppKit
import Foundation

final class ProbeLocation: NSObject, NSTextLocation {
  let offset: Int
  init(_ offset: Int) { self.offset = offset }
  func compare(_ other: any NSTextLocation) -> ComparisonResult {
    guard let value = other as? ProbeLocation else { return .orderedSame }
    return offset == value.offset
      ? .orderedSame : (offset < value.offset ? .orderedAscending : .orderedDescending)
  }
}

@MainActor final class Shaper {
  private let storage = NSTextContentStorage()
  private let backing = NSTextStorage()
  private let layout = NSTextLayoutManager()
  init() {
    storage.textStorage = backing
    storage.addTextLayoutManager(layout)
    storage.primaryTextLayoutManager = layout
    layout.textContainer = NSTextContainer(
      size: NSSize(width: 858, height: CGFloat.greatestFiniteMagnitude))
  }
  func lines(_ value: NSAttributedString) throws -> [(Int, Int, UInt)] {
    backing.setAttributedString(value)
    let doc = storage.documentRange
    let range = NSTextRange(location: doc.location, end: doc.endLocation)!
    layout.ensureLayout(for: range)
    var rows: [(Int, Int, UInt)] = []
    _ = layout.enumerateTextLayoutFragments(from: range.location, options: [.ensuresLayout]) {
      fragment in
      guard let r = fragment.textElement?.elementRange else { return false }
      let base = storage.offset(from: storage.documentRange.location, to: r.location)
      for line in fragment.textLineFragments {
        rows.append(
          (
            base + line.characterRange.location, line.characterRange.length,
            line.typographicBounds.width.bitPattern
          ))
      }
      return true
    }
    return rows
  }
}

final class ChunkManager: NSTextContentManager {
  let source: NSAttributedString
  let ranges: [(Int, Int)]
  private(set) var emitted = 0
  init(source: NSAttributedString, ranges: [(Int, Int)]) {
    self.source = source
    self.ranges = ranges
    super.init()
  }
  required init?(coder: NSCoder) { nil }
  override var documentRange: NSTextRange {
    NSTextRange(location: ProbeLocation(0), end: ProbeLocation(source.length))!
  }
  override func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (
    any NSTextLocation
  )? {
    guard let value = location as? ProbeLocation else { return nil }
    let next = value.offset + offset
    return (0...source.length).contains(next) ? ProbeLocation(next) : nil
  }
  override func offset(from: any NSTextLocation, to: any NSTextLocation) -> Int {
    guard let a = from as? ProbeLocation, let b = to as? ProbeLocation else { return NSNotFound }
    return b.offset - a.offset
  }
  override func enumerateTextElements(
    from location: (any NSTextLocation)?, options: NSTextContentManager.EnumerationOptions,
    using block: (NSTextElement) -> Bool
  ) -> (any NSTextLocation)? {
    let reverse = options.contains(.reverse)
    let offset = (location as? ProbeLocation)?.offset ?? (reverse ? source.length : 0)
    let values = reverse ? Array(ranges.reversed()) : ranges
    var last = ProbeLocation(offset)
    for (start, end) in values where (reverse ? end <= offset : end > offset) {
      let text = source.attributedSubstring(from: NSRange(location: start, length: end - start))
      let element = NSTextParagraph(attributedString: text)
      element.textContentManager = self
      element.elementRange = NSTextRange(location: ProbeLocation(start), end: ProbeLocation(end))!
      emitted += 1
      last = ProbeLocation(reverse ? start : end)
      if !block(element) { return last }
    }
    return last
  }
}

@MainActor final class ChunkView: NSView, @preconcurrency NSTextViewportLayoutControllerDelegate {
  let manager: ChunkManager
  let layout: NSTextLayoutManager
  let controller: NSTextViewportLayoutController
  var requestedViewport = CGRect.zero
  var fragments: [NSTextLayoutFragment] = []
  var renderOriginY: CGFloat = 0
  override var isFlipped: Bool { true }
  init(manager: ChunkManager, width: CGFloat, height: CGFloat) {
    self.manager = manager
    self.layout = NSTextLayoutManager()
    manager.addTextLayoutManager(layout)
    manager.primaryTextLayoutManager = layout
    let container = NSTextContainer(
      size: NSSize(width: width - 10, height: .greatestFiniteMagnitude))
    container.widthTracksTextView = true
    layout.textContainer = container
    controller = layout.textViewportLayoutController
    super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
    controller.delegate = self
  }
  required init?(coder: NSCoder) { nil }
  func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController) -> CGRect {
    requestedViewport
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
  ) {}
  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    for fragment in fragments {
      let viewportFrame = fragment.layoutFragmentFrame.offsetBy(dx: 0, dy: -renderOriginY)
      guard viewportFrame.intersects(dirtyRect) else { continue }
      fragment.draw(
        at: CGPoint(
          x: fragment.layoutFragmentFrame.minX, y: fragment.layoutFragmentFrame.minY - renderOriginY
        ), in: context)
    }
  }
}

@MainActor func plan(_ source: NSAttributedString) async throws -> (
  [(Int, Int)], [(Int, Int, UInt)]
) {
  let shaper = Shaper()
  var ranges: [(Int, Int)] = []
  var rows: [(Int, Int, UInt)] = []
  var start = 0
  while start < source.length {
    let count = min(4096, source.length - start)
    let candidate = source.attributedSubstring(from: NSRange(location: start, length: count))
    let lines = try shaper.lines(candidate)
    var end = start + count
    if end < source.length && lines.count > 1 {
      end = start + lines[lines.count - 2].0 + lines[lines.count - 2].1
    }
    let complete = end == start + count ? lines : Array(lines.dropLast())
    guard end > start else { throw NSError(domain: "probe", code: 1) }
    ranges.append((start, end))
    rows.append(contentsOf: complete.map { (start + $0.0, $0.1, $0.2) })
    start = end
    if ranges.count.isMultiple(of: 200) { fputs("plan=\(ranges.count) covered=\(start)\n", stderr) }
    await Task.yield()
  }
  return (ranges, rows)
}

@MainActor func run() async throws {
  let header = "123456789012345\n"
  let text = header + String(repeating: "خط📝", count: (10_485_760 - 16) / 8)
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let source = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
  let began = ProcessInfo.processInfo.systemUptime
  let (ranges, expected) = try await plan(source)
  let planSeconds = ProcessInfo.processInfo.systemUptime - began
  fputs("planned chunks=\(ranges.count) lines=\(expected.count) seconds=\(planSeconds)\n", stderr)
  let manager = ChunkManager(source: source, ranges: ranges)
  let view = ChunkView(manager: manager, width: 868, height: 500)
  for (label, target) in [
    ("start", 0), ("middle", source.length / 2), ("end", source.length - 1024),
  ] {
    let requestedEnd = min(source.length, target + 1024)
    let a = manager.location(manager.documentRange.location, offsetBy: target)!
    let b = manager.location(a, offsetBy: requestedEnd - target)!
    let requested = NSTextRange(location: a, end: b)!
    view.fragments.removeAll(keepingCapacity: true)
    let before = ProcessInfo.processInfo.systemUptime
    view.layout.ensureLayout(for: requested)
    var actual: [(Int, Int, UInt)] = []
    _ = view.layout.enumerateTextLayoutFragments(from: a, options: [.ensuresLayout]) { fragment in
      view.fragments.append(fragment)
      guard let elementRange = fragment.textElement?.elementRange else { return false }
      let base = manager.offset(from: manager.documentRange.location, to: elementRange.location)
      for line in fragment.textLineFragments {
        actual.append(
          (
            base + line.characterRange.location, line.characterRange.length,
            line.typographicBounds.width.bitPattern
          ))
      }
      return actual.last.map { $0.0 + $0.1 < requestedEnd } ?? true
    }
    view.renderOriginY = view.fragments.first?.layoutFragmentFrame.minY ?? 0
    let expectedSlice = expected.filter { $0.0 < requestedEnd && $0.0 + $0.1 > target }
    let actualSlice = actual.filter { $0.0 < requestedEnd && $0.0 + $0.1 > target }
    let exact =
      expectedSlice.count == actualSlice.count
      && zip(expectedSlice, actualSlice).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 868, pixelsHigh: 500, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)
    else { throw NSError(domain: "probe", code: 2) }
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.cgContext.setFillColor(NSColor.white.cgColor)
    graphics.cgContext.fill(CGRect(x: 0, y: 0, width: 868, height: 500))
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    let pixels =
      bitmap.bitmapData.map { Data(bytes: $0, count: bitmap.bytesPerRow * bitmap.pixelsHigh) }
      ?? Data()
    var nonWhite = 0
    for index in stride(from: 0, to: pixels.count - 3, by: 4)
    where pixels[index] < 240 || pixels[index + 1] < 240 || pixels[index + 2] < 240 {
      nonWhite += 1
    }
    let elapsed = ProcessInfo.processInfo.systemUptime - before
    print(
      "target=\(label) offset=\(target) fragments=\(view.fragments.count) lines=\(actual.count) exactGeometry=\(exact) nonWhitePixels=\(nonWhite) elapsedMs=\(elapsed * 1000)"
    )
  }
}

@main @MainActor enum Main {
  static func main() async throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    try await run()
  }
}
