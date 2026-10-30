import AppKit
import XCTest

@MainActor
final class LongTextLineIndexTests: XCTestCase {
  func testIndexMatchesNativeTextKitForUnicodeAndHardLineBreaks() throws {
    let fixtures = [
      String(repeating: "خط📝 عربي🙂 ", count: 300),
      String(repeating: "English עברית 123 — punctuation! ", count: 250),
      String(repeating: "e\u{301} 🧑🏽‍💻 👨‍👩‍👧‍👦\r\n", count: 200),
      String(repeating: "first\rsecond\u{0085}third\u{2028}fourth\u{2029}", count: 150),
    ]
    for (fixtureIndex, text) in fixtures.enumerated() {
      let expected = try nativeLineGeometry(
        for: text, width: 280,
        font: .monospacedSystemFont(ofSize: 14, weight: .regular)
      ).map(\.range)
      let index = try LongTextLineIndexer.makeIndex(
        text: text, fontName: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular).fontName,
        fontSize: 14, textWidth: 270, windowSize: 8_192)
      let actual = index.lines.map(\.range)
      let firstMismatch = zip(actual, expected).enumerated().first {
        $0.element.0 != $0.element.1
      }
      XCTAssertEqual(
        actual.count, expected.count,
        "fixture \(fixtureIndex) line counts differ: indexed \(actual.count), native \(expected.count)"
      )
      XCTAssertNil(
        firstMismatch,
        "fixture \(fixtureIndex) first range mismatch at \(String(describing: firstMismatch))")
      XCTAssertEqual(index.lines.first?.range.lowerBound, 0)
      XCTAssertEqual(index.lines.last?.range.upperBound, text.utf16.count)
      XCTAssertEqual(index.lineIndex(atUTF16Offset: 0), 0)
      XCTAssertEqual(index.lineIndex(atY: 0), 0)
    }
  }

  func testIndexVerticalGeometryMatchesNativeTextKitFontMetrics() throws {
    let fonts = [
      NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
      NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
      NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
      NSFont.monospacedSystemFont(ofSize: 18, weight: .regular),
      NSFont.monospacedSystemFont(ofSize: 24, weight: .regular),
      NSFont.systemFont(ofSize: 36),
      try XCTUnwrap(NSFont(name: "Menlo", size: 14)),
    ]
    let text = String(repeating: "Mixed العربية 🧑🏽‍💻 tabs e\u{301} ", count: 120)

    for font in fonts {
      let expected = try nativeLineGeometry(for: text, width: 420, font: font)
      let index = try LongTextLineIndexer.makeIndex(
        text: text, fontName: font.fontName, fontSize: font.pointSize, textWidth: 410,
        windowSize: 4_096)

      XCTAssertEqual(index.lines.count, expected.count, "line count for \(font.fontName)")
      for (lineIndex, pair) in zip(index.lines, expected).enumerated() {
        XCTAssertEqual(pair.0.range, pair.1.range, "line range for \(font.fontName)")
        XCTAssertEqual(
          pair.0.y, pair.1.y, accuracy: 0.01,
          "vertical position for \(font.fontName), line \(lineIndex)")
        XCTAssertEqual(
          pair.0.height, pair.1.height, accuracy: 0.01,
          "line height for \(font.fontName), line \(lineIndex)")
      }
    }
  }

  func testTenMiBArabicParagraphHasCompleteIndexedCoverage() throws {
    let text = String(repeating: "خط📝", count: 1_310_720)
    XCTAssertEqual(text.utf8.count, 10_485_760)
    let index = try LongTextLineIndexer.makeIndex(
      text: text, fontName: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular).fontName,
      fontSize: 14, textWidth: 840)
    XCTAssertEqual(index.lines.first?.range.lowerBound, 0)
    XCTAssertEqual(index.lines.last?.range.upperBound, text.utf16.count)
    XCTAssertTrue(
      zip(index.lines, index.lines.dropFirst()).allSatisfy {
        $0.range.upperBound == $1.range.lowerBound && $0.y + $0.height == $1.y
      })
    XCTAssertNotNil(index.lineIndex(atUTF16Offset: text.utf16.count / 2))
    XCTAssertNotNil(index.lineIndex(atY: index.height / 2))
    for y in [CGFloat.zero, index.height / 2, max(0, index.height - 500)] {
      let visibleLines = try XCTUnwrap(
        index.visibleLineRange(atY: y, viewportHeight: 500, overscan: 4))
      let visibleText = try XCTUnwrap(index.textRange(for: visibleLines))
      XCTAssertLessThanOrEqual(visibleLines.count, 40)
      XCTAssertEqual(visibleText.lowerBound, index.lines[visibleLines.lowerBound].range.lowerBound)
      XCTAssertEqual(
        visibleText.upperBound, index.lines[visibleLines.upperBound - 1].range.upperBound)
    }
  }

  private func nativeLineGeometry(for text: String, width: CGFloat, font: NSFont) throws
    -> [(range: Range<Int>, y: CGFloat, height: CGFloat)]
  {
    let editor = NSTextView(usingTextLayoutManager: true)
    guard let storage = editor.textStorage,
      let manager = editor.textLayoutManager,
      let container = editor.textContainer,
      let content = manager.textContentManager as? NSTextContentStorage
    else { throw XCTSkip("TextKit 2 unavailable") }
    editor.font = font
    editor.textContainerInset = .zero
    container.lineFragmentPadding = 5
    container.widthTracksTextView = false
    container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
    storage.setAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    let documentRange = manager.documentRange
    manager.ensureLayout(for: documentRange)
    var lines: [(range: Range<Int>, y: CGFloat, height: CGFloat)] = []
    _ = manager.enumerateTextLayoutFragments(
      from: documentRange.location, options: [.ensuresLayout]
    ) {
      fragment in
      guard let elementRange = fragment.textElement?.elementRange else { return true }
      let base = content.offset(from: documentRange.location, to: elementRange.location)
      guard base != NSNotFound, base >= 0 else { return true }
      for line in fragment.textLineFragments {
        let start = base + line.characterRange.location
        lines.append(
          (
            start..<(start + line.characterRange.length),
            fragment.layoutFragmentFrame.minY + line.typographicBounds.minY,
            line.typographicBounds.height
          ))
      }
      return true
    }
    return lines
  }
}
