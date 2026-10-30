@preconcurrency import AppKit
import CoreText
import Foundation

@MainActor
private struct IndexedLine {
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

@MainActor
private struct LinePlan {
  let lines: [IndexedLine]
  let height: CGFloat
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
    for line in fragment.textLineFragments {
      rows.append(GeometryRow(
        start: line.characterRange.location,
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
  let fixtures = [
    ("rtl-emoji", String(repeating: "خط📝", count: 2_000), 320.0, 65_536),
    ("mixed-bidi", String(repeating: "abc اردو 123 — שלום🙂 ", count: 600), 420.0, 65_536),
    ("combining", String(repeating: "e\u{301} العربية אבג 🧑🏽‍💻 ", count: 600), 420.0, 8_192),
    ("punctuation", String(repeating: "(rtl: العربية 42) [עברית, 7] — 🙂 ", count: 600), 420.0, 65_536),
  ]
  for (name, text, width, window) in fixtures {
    let source = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
    let plan = try makePlan(source, width: width, window: window)
    let expected = try nativeGeometry(source, width: width)
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
      let localRows = try nativeGeometry(slice, width: width)
      guard localRows.count == last - first else {
        throw NSError(domain: "line-index", code: 13, userInfo: [NSLocalizedDescriptionKey: "\(name): slice at line \(first) has \(localRows.count), expected \(last - first) lines"])
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
private func makePlan(_ source: NSAttributedString, width: CGFloat, window: Int) throws -> LinePlan {
  let textWidth = max(1, width - 10) // Match NSTextContainer's default 5 point padding on each side.
  var spans: [Range<Int>] = []
  var heightByRange: [Range<Int>: CGFloat] = [:]
  var widthByRange: [Range<Int>: Double] = [:]
  var start = 0
  while start < source.length {
    let count = min(window, source.length - start)
    let candidate = source.attributedSubstring(from: NSRange(location: start, length: count))
    let typesetter = CTTypesetterCreateWithAttributedString(candidate as CFAttributedString)
    var local: [Range<Int>] = []
    var offset = 0
    while offset < candidate.length {
      let length = CTTypesetterSuggestLineBreak(typesetter, offset, Double(textWidth))
      guard length > 0 else { throw NSError(domain: "line-index", code: 1) }
      let range = (start + offset)..<(start + offset + length)
      local.append(range)
      let line = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: length))
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
      heightByRange[range] = max(1, ceil(ascent + descent + leading))
      widthByRange[range] = width
      offset += length
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

@MainActor
private final class IndexedSliceView: NSView {
  private let source: NSAttributedString
  private let plan: LinePlan
  private var fragments: [NSTextLayoutFragment] = []
  private var drawOriginY: CGFloat = 0
  private let viewportHeight: CGFloat
  private(set) var displayedRange: Range<Int> = 0..<0
  private(set) var displayedLineCount = 0

  override var isFlipped: Bool { true }

  init(source: NSAttributedString, plan: LinePlan, width: CGFloat, viewportHeight: CGFloat) {
    self.source = source
    self.plan = plan
    self.viewportHeight = viewportHeight
    super.init(frame: NSRect(x: 0, y: 0, width: width, height: max(viewportHeight, plan.height)))
  }

  required init?(coder: NSCoder) { nil }

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
    drawOriginY = plan.lines[first].y
    displayedRange = start..<end
    displayedLineCount = actualLineCount
    needsDisplay = true
  }

  func indexedY(for rangeStart: Int) -> CGFloat {
    plan.lines.first(where: { $0.range.lowerBound == rangeStart })?.y ?? 0
  }

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
    let planStart = ContinuousClock.now
    let plan = try makePlan(source, width: 858, window: 65_536)
    let planDuration = planStart.duration(to: .now)

    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = false
    let view = IndexedSliceView(source: source, plan: plan, width: 868, viewportHeight: 500)
    scroll.documentView = view
    let window = NSWindow(contentRect: scroll.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = scroll

    print("planBytes=\(text.utf8.count) utf16=\(source.length) lines=\(plan.lines.count) height=\(plan.height) plan=\(planDuration)")
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
  }
}
