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

  init(source: NSAttributedString, line: CTLine, range: NSRange, bounds: CGRect, ascent: CGFloat) {
    self.source = source
    self.ctLine = line
    self.sourceRange = range
    self.bounds = bounds
    self.ascent = ascent
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
    return CGPoint(x: CTLineGetOffsetForStringIndex(ctLine, clamped, nil), y: 0)
  }
  override func characterIndex(for point: CGPoint) -> Int {
    CTLineGetStringIndexForPosition(ctLine, CGPoint(x: point.x, y: 0))
  }
  override func fractionOfDistanceThroughGlyph(for point: CGPoint) -> CGFloat {
    let index = CTLineGetStringIndexForPosition(ctLine, CGPoint(x: point.x, y: 0))
    var secondary: CGFloat = 0
    let primary = CTLineGetOffsetForStringIndex(ctLine, index, &secondary)
    let nextIndex = min(NSMaxRange(sourceRange), index + 1)
    let next = CTLineGetOffsetForStringIndex(ctLine, nextIndex, nil)
    let span = next - primary
    return abs(span) < .ulpOfOne ? 0 : max(0, min(1, (point.x - primary) / span))
  }
}

final class ProbeFragment: NSTextLayoutFragment {
  let lines: [NSTextLineFragment]
  let frame: CGRect
  init(element: NSTextElement, lines: [NSTextLineFragment], frame: CGRect) {
    self.lines = lines
    self.frame = frame
    super.init(textElement: element, range: element.elementRange)
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
  func textLayoutManager(
    _ textLayoutManager: NSTextLayoutManager,
    textLayoutFragmentFor location: any NSTextLocation,
    in textElement: NSTextElement
  ) -> NSTextLayoutFragment {
    calls += 1
    fputs("delegate-start call=\(calls) range=\(String(describing: textElement.elementRange))\n", stderr)
    fflush(stderr)
    let source = (textElement as! NSTextParagraph).attributedString
    let width: CGFloat = 858
    let shapeStart = ProcessInfo.processInfo.systemUptime
    let setter = CTFramesetterCreateWithAttributedString(source as CFAttributedString)
    let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude), transform: nil)
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: source.length), path, nil)
    let ctLines = CTFrameGetLines(frame) as! [CTLine]
    var origins = Array(repeating: CGPoint.zero, count: ctLines.count)
    CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
    var lines: [NSTextLineFragment] = []
    lines.reserveCapacity(ctLines.count)
    for (index, line) in ctLines.enumerated() {
      let cfRange = CTLineGetStringRange(line)
      let range = NSRange(location: cfRange.location, length: cfRange.length)
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
      let top = max(0, origins.first!.y - origins[index].y)
      let lineHeight = max(1, ascent + descent + leading)
      lines.append(CoreTextLineFragment(
        source: source, line: line, range: range,
        bounds: CGRect(x: 0, y: top, width: lineWidth, height: lineHeight), ascent: ascent))
    }
    shapeSeconds = ProcessInfo.processInfo.systemUptime - shapeStart
    fputs("delegate-shaped call=\(calls) seconds=\(shapeSeconds) lines=\(lines.count)\n", stderr)
    fflush(stderr)
    lineCount = lines.count
    let height = lines.last.map { $0.typographicBounds.maxY } ?? 20
    return ProbeFragment(element: textElement, lines: lines, frame: CGRect(x: 0, y: 0, width: width, height: height))
  }
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
    let duration = ProcessInfo.processInfo.systemUptime - start
    let caretSeconds = 0.0
    let caretRect = CGRect.zero
    let selectedRange = NSRange(location: 0, length: 0)
    let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    print("bytes=\(text.utf8.count) digest=\(digest) utf16=\(attributed.length) elapsed=\(duration) caretSeconds=\(caretSeconds) caretRect=\(NSStringFromRect(caretRect)) selected=\(NSStringFromRange(selectedRange)) delegateCalls=\(delegate.calls) shapeSeconds=\(delegate.shapeSeconds) lines=\(delegate.lineCount) state=\(manager.textLayoutFragment(for: manager.documentRange.location)?.state.rawValue ?? 0)")
  }
}
