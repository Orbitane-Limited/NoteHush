@preconcurrency import AppKit
import CoreText
import CryptoKit
import Foundation

final class CoreTextLineFragment: NSTextLineFragment {
  private let source: NSAttributedString
  private let ctLine: CTLine
  private let sourceRange: NSRange
  private let bounds: CGRect
  private let ascent: CGFloat
  private let lineBaseOffset: Int

  init(source: NSAttributedString, line: CTLine, range: NSRange, bounds: CGRect, ascent: CGFloat, lineBaseOffset: Int) {
    self.source = source
    self.ctLine = line
    self.sourceRange = range
    self.bounds = bounds
    self.ascent = ascent
    self.lineBaseOffset = lineBaseOffset
    super.init(attributedString: source, range: NSRange(location: 0, length: 0))
  }
  required init?(coder: NSCoder) { return nil }
  override var attributedString: NSAttributedString { source }
  override var characterRange: NSRange { sourceRange }
  override var typographicBounds: CGRect { bounds }
  override var glyphOrigin: CGPoint { CGPoint(x: 0, y: bounds.minY + ascent) }
  override func draw(at point: CGPoint, in context: CGContext) {
    context.saveGState()
    context.textPosition = CGPoint(x: point.x, y: point.y + bounds.minY + ascent)
    CTLineDraw(ctLine, context)
    context.restoreGState()
  }
  override func locationForCharacter(at index: Int) -> CGPoint {
    let clamped = max(sourceRange.location, min(index, NSMaxRange(sourceRange)))
    return CGPoint(x: CTLineGetOffsetForStringIndex(ctLine, clamped - lineBaseOffset, nil), y: 0)
  }
  override func characterIndex(for point: CGPoint) -> Int {
    lineBaseOffset + CTLineGetStringIndexForPosition(ctLine, CGPoint(x: point.x, y: 0))
  }
  override func fractionOfDistanceThroughGlyph(for point: CGPoint) -> CGFloat {
    let localIndex = CTLineGetStringIndexForPosition(ctLine, CGPoint(x: point.x, y: 0))
    var secondary: CGFloat = 0
    let primary = CTLineGetOffsetForStringIndex(ctLine, localIndex, &secondary)
    let nextIndex = min(NSMaxRange(sourceRange) - lineBaseOffset, localIndex + 1)
    let next = CTLineGetOffsetForStringIndex(ctLine, nextIndex, nil)
    let span = next - primary
    return abs(span) < .ulpOfOne ? 0 : max(0, min(1, (point.x - primary) / span))
  }
}

final class ProbeFragment: NSTextLayoutFragment {
  let lines: [NSTextLineFragment]
  let frame: CGRect
  init(element: NSTextElement, range: NSTextRange, lines: [NSTextLineFragment], frame: CGRect) {
    self.lines = lines
    self.frame = frame
    super.init(textElement: element, range: range)
  }
  required init?(coder: NSCoder) { return nil }
  override var textLineFragments: [NSTextLineFragment] { lines }
  override var layoutFragmentFrame: CGRect { frame }
  override var renderingSurfaceBounds: CGRect { frame }
  override var state: NSTextLayoutFragment.State { .layoutAvailable }
  override func draw(at point: CGPoint, in context: CGContext) {
    for line in lines { line.draw(at: point, in: context) }
  }
}

@MainActor final class ProbeDelegate: NSObject, @preconcurrency NSTextLayoutManagerDelegate {
  var calls = 0
  var lineCount = 0
  var shapeSeconds = 0.0
  var latestLineRows: [(Int, Int, UInt)] = []
  func textLayoutManager(
    _ textLayoutManager: NSTextLayoutManager,
    textLayoutFragmentFor location: any NSTextLocation,
    in textElement: NSTextElement
  ) -> NSTextLayoutFragment {
    calls += 1
    fputs("delegate-start call=\(calls) range=\(String(describing: textElement.elementRange))\n", stderr)
    fflush(stderr)
    guard let paragraph = textElement as? NSTextParagraph,
      let content = textLayoutManager.textContentManager,
      let elementRange = textElement.elementRange else { preconditionFailure("Missing paragraph content") }
    let source = paragraph.attributedString
    let requested = content.offset(from: elementRange.location, to: location)
    fputs("delegate-request call=\(calls) localOffset=\(requested)\n", stderr)
    let maxFragmentUnits = 4096
    let chunkStart = max(0, min(source.length - 1, (requested / maxFragmentUnits) * maxFragmentUnits))
    let shapeLength = min(maxFragmentUnits * 2, source.length - chunkStart)
    let chunkRange = NSRange(location: chunkStart, length: shapeLength)
    let shapedSource = source.attributedSubstring(from: chunkRange)
    let width: CGFloat = 858
    let shapeStart = ProcessInfo.processInfo.systemUptime
    let setter = CTFramesetterCreateWithAttributedString(shapedSource as CFAttributedString)
    let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude), transform: nil)
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: shapedSource.length), path, nil)
    let ctLines = CTFrameGetLines(frame) as! [CTLine]
    var lines: [NSTextLineFragment] = []
    lines.reserveCapacity(ctLines.count)
    var top: CGFloat = 0
    for line in ctLines {
      let cfRange = CTLineGetStringRange(line)
      let range = NSRange(location: cfRange.location, length: cfRange.length)
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
      let lineHeight = max(1, ascent + descent + leading)
      lines.append(CoreTextLineFragment(
        source: source, line: line,
        range: NSRange(location: chunkStart + range.location, length: range.length),
        bounds: CGRect(x: 0, y: top, width: lineWidth, height: lineHeight), ascent: ascent,
        lineBaseOffset: chunkStart))
      top += lineHeight
    }
    let fragmentLimit = min(source.length, chunkStart + maxFragmentUnits)
    let completeLines = lines.filter { NSMaxRange($0.characterRange) <= fragmentLimit }
    guard let lastCompleteLine = completeLines.last else {
      preconditionFailure("No complete line fits in bounded fragment")
    }
    let plannedEnd = NSMaxRange(lastCompleteLine.characterRange)
    lines = completeLines
    guard let fragmentStart = content.location(elementRange.location, offsetBy: chunkStart),
      let fragmentEnd = content.location(elementRange.location, offsetBy: plannedEnd),
      let fragmentRange = NSTextRange(location: fragmentStart, end: fragmentEnd) else {
      preconditionFailure("Missing aligned fragment range")
    }
    shapeSeconds = ProcessInfo.processInfo.systemUptime - shapeStart
    fputs("delegate-shaped call=\(calls) seconds=\(shapeSeconds) lines=\(lines.count) range=\(chunkStart)-\(plannedEnd)\n", stderr)
    fflush(stderr)
    lineCount = lines.count
    fputs("lineTopSamples=\(lines.prefix(5).map { $0.typographicBounds.minY })\n", stderr)
    latestLineRows = lines.map { line in
      (line.characterRange.location, line.characterRange.length, line.typographicBounds.width.bitPattern)
    }
    let height = lines.last.map { $0.typographicBounds.maxY } ?? 20
    return ProbeFragment(element: textElement, range: fragmentRange, lines: lines, frame: CGRect(x: 0, y: 0, width: width, height: height))
  }
}

func elementRangeForProbe(_ content: NSTextContentManager, header: String) -> NSTextRange {
  guard let bodyStart = content.location(content.documentRange.location, offsetBy: header.utf16.count),
    let range = NSTextRange(location: bodyStart, end: content.documentRange.endLocation)
  else { preconditionFailure("Missing body range") }
  return range
}

@main @MainActor enum Main {
  static func main() {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let bytes = Int(CommandLine.arguments.dropFirst().first ?? "16384") ?? 16384
    let unit = "خط📝"
    let header = "123456789012345\n"
    let repeats = max(1, (bytes - header.utf8.count) / unit.utf8.count)
    let text = header + String(repeating: unit, count: repeats)
    let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    let style = NSMutableParagraphStyle()
    style.baseWritingDirection = .natural
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
    let view = NSTextView(usingTextLayoutManager: true)
    view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
    view.isRichText = false
    view.textContainerInset = NSSize(width: 16, height: 16)
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    scroll.documentView = view
    view.layoutSubtreeIfNeeded()
    let manager = view.textLayoutManager!
    manager.textContainer!.containerSize = NSSize(width: 858, height: CGFloat.greatestFiniteMagnitude)
    let delegate = ProbeDelegate()
    manager.delegate = delegate
    view.textStorage?.setAttributedString(attributed)
    print("stage=assigned bytes=\(text.utf8.count)")
    fflush(stdout)
    let start = ProcessInfo.processInfo.systemUptime
    manager.ensureLayout(for: CGRect(x: 0, y: 0, width: 858, height: 600))
    print("stage=ensured seconds=\(ProcessInfo.processInfo.systemUptime - start)")
    fflush(stdout)
    guard let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 600,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
      preconditionFailure("Could not create render bitmap")
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(
      to: URL(fileURLWithPath: "/private/tmp/BoundedCoreTextFragment-\(bytes).png"))
    var nonWhite = 0
    if let pixels = bitmap.bitmapData {
      for offset in stride(from: 0, to: bitmap.bytesPerRow * 600, by: 4) {
        if pixels[offset] < 240 || pixels[offset + 1] < 240 || pixels[offset + 2] < 240 {
          nonWhite += 1
        }
      }
    }
    print("renderBitmapNonWhitePixels=\(nonWhite)")
    fflush(stdout)
    if let manager = view.textLayoutManager, let content = manager.textContentManager {
      let bodyLength = max(0, attributed.length - header.utf16.count)
      let offsets = [0, min(5000, bodyLength - 1), max(0, bodyLength / 2), max(0, bodyLength - 4096)]
      for offset in offsets {
        guard let start = content.location(content.documentRange.location, offsetBy: header.utf16.count + offset),
          let end = content.location(start, offsetBy: min(128, bodyLength - offset)),
          let range = NSTextRange(location: start, end: end) else { continue }
        let requestStart = ProcessInfo.processInfo.systemUptime
        manager.invalidateLayout(for: range)
        manager.ensureLayout(for: range)
        let requestMs = (ProcessInfo.processInfo.systemUptime - requestStart) * 1000
        var fragment = manager.textLayoutFragment(for: start)
        if fragment == nil {
          manager.invalidateLayout(for: elementRangeForProbe(content, header: header))
          manager.ensureLayout(for: range)
          fragment = manager.textLayoutFragment(for: start)
        }
        let fragmentStart = fragment.flatMap { $0.rangeInElement.location }
          .map { content.offset(from: content.documentRange.location, to: $0) }
        let fragmentEnd = fragment.flatMap { $0.rangeInElement.endLocation }
          .map { content.offset(from: content.documentRange.location, to: $0) }
        print("targetOffset=\(offset) requestMs=\(requestMs) fragment=\(String(describing: fragmentStart))-\(String(describing: fragmentEnd)) state=\(fragment?.state.rawValue ?? 0) lines=\(fragment?.textLineFragments.count ?? 0)")
        fflush(stdout)
      }
    }
    let duration = ProcessInfo.processInfo.systemUptime - start
    var smallControl = "not-run"
    if bytes == 16384 {
      let baselineStorage = NSTextStorage()
      let baselineContent = NSTextContentStorage()
      baselineContent.textStorage = baselineStorage
      let baselineLayout = NSTextLayoutManager()
      baselineContent.addTextLayoutManager(baselineLayout)
      baselineLayout.textContainer = NSTextContainer(
        size: NSSize(width: 858, height: CGFloat.greatestFiniteMagnitude))
      baselineContent.performEditingTransaction { baselineStorage.setAttributedString(attributed) }
      baselineLayout.ensureLayout(for: baselineContent.documentRange)
      var nativeRows: [(Int, Int, UInt)] = []
      _ = baselineLayout.enumerateTextLayoutFragments(
        from: baselineContent.documentRange.location, options: []) { fragment in
        guard let elementRange = fragment.textElement?.elementRange else { return false }
        let base = baselineContent.offset(
          from: baselineContent.documentRange.location, to: elementRange.location)
        for line in fragment.textLineFragments {
          nativeRows.append((base + line.characterRange.location,
                             line.characterRange.length,
                             line.typographicBounds.width.bitPattern))
        }
        return true
      }
      let customRows = delegate.latestLineRows
      let comparableNative = nativeRows
        .filter { $0.0 >= 16 && $0.0 < 16 + 4096 && $0.0 + $0.1 <= 16 + 4096 }
        .map { ($0.0 - 16, $0.1, $0.2) }
      let sameRange = comparableNative.count == customRows.count
        && zip(comparableNative, customRows).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
      let sameWidth = comparableNative.count == customRows.count
        && zip(comparableNative, customRows).allSatisfy { $0.2 == $1.2 }
      var firstDifference = "none"
      for (index, pair) in zip(comparableNative, customRows).enumerated() {
        if pair.0.0 != pair.1.0 || pair.0.1 != pair.1.1 || pair.0.2 != pair.1.2 {
          firstDifference = "index=\(index) native=\(pair.0) partial=\(pair.1)"
          break
        }
      }
      smallControl = "nativeRows=\(comparableNative.count) partialRows=\(customRows.count) startsAndLengthsExact=\(sameRange) widthsExact=\(sameWidth) firstDiff=\(firstDifference)"
    }
    let caretSeconds = 0.0
    let caretRect = CGRect.zero
    let selectedRange = NSRange(location: 0, length: 0)
    let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    print("bytes=\(text.utf8.count) digest=\(digest) utf16=\(attributed.length) elapsed=\(duration) caretSeconds=\(caretSeconds) caretRect=\(NSStringFromRect(caretRect)) selected=\(NSStringFromRange(selectedRange)) delegateCalls=\(delegate.calls) shapeSeconds=\(delegate.shapeSeconds) lines=\(delegate.lineCount) smallControl=\(smallControl) state=\(manager.textLayoutFragment(for: manager.documentRange.location)?.state.rawValue ?? 0)")
  }
}
