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
      let expected = try nativeLines(for: text, width: 280)
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

  private func nativeLines(for text: String, width: CGFloat) throws -> [Range<Int>] {
    let editor = NSTextView(usingTextLayoutManager: true)
    guard let storage = editor.textStorage,
      let manager = editor.textLayoutManager,
      let container = editor.textContainer,
      let content = manager.textContentManager as? NSTextContentStorage
    else { throw XCTSkip("TextKit 2 unavailable") }
    let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    editor.font = font
    editor.textContainerInset = .zero
    container.lineFragmentPadding = 5
    container.widthTracksTextView = false
    container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
    storage.setAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    let documentRange = manager.documentRange
    manager.ensureLayout(for: documentRange)
    var ranges: [Range<Int>] = []
    _ = manager.enumerateTextLayoutFragments(
      from: documentRange.location, options: [.ensuresLayout]
    ) {
      fragment in
      guard let elementRange = fragment.textElement?.elementRange else { return true }
      let base = content.offset(from: documentRange.location, to: elementRange.location)
      guard base != NSNotFound, base >= 0 else { return true }
      for line in fragment.textLineFragments {
        let start = base + line.characterRange.location
        ranges.append(start..<(start + line.characterRange.length))
      }
      return true
    }
    return ranges
  }
}
