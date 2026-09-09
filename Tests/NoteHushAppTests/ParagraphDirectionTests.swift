import AppKit
import CoreFoundation
import XCTest

@MainActor
final class ParagraphDirectionTests: XCTestCase {
  func testNaturalProjectionMatchesNativeUnicodeDirectionsWithoutChangingStorage() throws {
    guard #available(macOS 26.0, *) else { throw XCTSkip("Statistical API starts on macOS 26") }
    let phrases = [
      "English letters 123 .", "اردو عربی فارسی ۱۲۳", "עברית 123: English!",
      "خط e\u{301} 📝.", "👩🏽‍💻 👨‍👩‍👧‍👦 🇵🇰 e\u{301}", " 123 !? () [] ", "",
      "English \u{2067}עברית 123\u{2069} tail", "عربي \u{2066}English 123\u{2069} آخر",
      "prefix \u{202B}אבג\u{202C} suffix", "\u{2068}مرحبا\u{2069} punctuation...",
      "English English عربي", "English عربي عربي", "\u{200F}123\u{200E}",
    ]
    for phrase in phrases {
      for separator in ["\n", "\r", "\r\n", "\u{0085}", "\u{2028}", "\u{2029}"] {
        for alignment in [NSTextAlignment.natural, .left] {
          let style = NSMutableParagraphStyle()
          style.alignment = alignment
          style.lineSpacing = 2
          style.headIndent = 4
          style.firstLineHeadIndent = 4
          let text = "English prefix" + separator + phrase + separator + "نهاية عربية" + separator
          let source = NSAttributedString(
            string: text,
            attributes: [.paragraphStyle: style, .foregroundColor: NSColor.systemBlue, .kern: 1.25])
          let content = NSTextContentStorage()
          let storage = NSTextStorage(attributedString: source)
          content.textStorage = storage
          storage.ensureAttributesAreFixed(in: NSRange(location: 0, length: storage.length))
          let before = NSAttributedString(attributedString: storage)
          let presenter = ParagraphDirectionPresenter()
          var offset = 0
          while offset < storage.length {
            let range = (text as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
            let original = before.attributedSubstring(from: range)
            let expected = statisticalDirections(before, range: range)
            XCTAssertEqual(
              expected,
              statisticalDirections(original, range: NSRange(location: 0, length: original.length)))
            let paragraph = presenter.textContentStorage(content, textParagraphWith: range)
            if let first = expected.first, first <= 1, expected.allSatisfy({ $0 == first }) {
              let presented = try XCTUnwrap(paragraph?.attributedString)
              XCTAssertEqual(Array(presented.string.utf8), Array(original.string.utf8))
              XCTAssertEqual(presented.length, original.length)
              for index in 0..<original.length {
                var oldAttributes = original.attributes(at: index, effectiveRange: nil)
                var newAttributes = presented.attributes(at: index, effectiveRange: nil)
                let oldStyle =
                  oldAttributes.removeValue(forKey: .paragraphStyle) as? NSParagraphStyle
                  ?? .default
                let newStyle = try XCTUnwrap(
                  newAttributes.removeValue(forKey: .paragraphStyle) as? NSParagraphStyle)
                XCTAssertTrue(NSDictionary(dictionary: oldAttributes).isEqual(to: newAttributes))
                XCTAssertEqual(
                  newStyle.baseWritingDirection, first == 0 ? .leftToRight : .rightToLeft)
                let restoredStyle = try XCTUnwrap(
                  newStyle.mutableCopy() as? NSMutableParagraphStyle)
                restoredStyle.baseWritingDirection = oldStyle.baseWritingDirection
                XCTAssertTrue(restoredStyle.isEqual(oldStyle))
              }
            } else {
              XCTAssertNil(paragraph)
            }
            XCTAssertTrue(storage.isEqual(to: before))
            offset = NSMaxRange(range)
          }
        }
      }
    }
  }

  func testExplicitWritingDirectionsRemainNative() {
    for direction in [NSWritingDirection.leftToRight, .rightToLeft] {
      let style = NSMutableParagraphStyle()
      style.baseWritingDirection = direction
      let source = NSAttributedString(
        string: "English عربي\r\n", attributes: [.paragraphStyle: style])
      let content = NSTextContentStorage()
      content.textStorage = NSTextStorage(attributedString: source)
      let paragraph = ParagraphDirectionPresenter().textContentStorage(
        content, textParagraphWith: NSRange(location: 0, length: source.length))
      XCTAssertNil(paragraph)
      XCTAssertEqual(content.textStorage?.string, source.string)
      XCTAssertEqual(
        (content.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
          as? NSParagraphStyle)?
          .baseWritingDirection, direction)
    }
  }

  func testEmptyAndOversizeParagraphsKeepNativePresentation() {
    let presenter = ParagraphDirectionPresenter()
    let content = NSTextContentStorage()
    XCTAssertNil(
      presenter.textContentStorage(content, textParagraphWith: NSRange(location: 0, length: 0)))
    let text = String(repeating: "a", count: 1_048_577)
    content.textStorage = NSTextStorage(string: text)
    XCTAssertNil(
      presenter.textContentStorage(
        content, textParagraphWith: NSRange(location: 0, length: text.utf16.count)))
    XCTAssertEqual(content.textStorage?.string, text)
  }

  @available(macOS 26.0, *)
  private func statisticalDirections(_ text: NSAttributedString, range: NSRange) -> [UInt8] {
    var levels = [UInt8](repeating: 253, count: range.length)
    var directions = [UInt8](repeating: 253, count: range.length)
    levels.withUnsafeMutableBufferPointer { levelBuffer in
      directions.withUnsafeMutableBufferPointer { directionBuffer in
        _ = CFAttributedStringGetStatisticalWritingDirections(
          text as CFAttributedString, CFRange(location: range.location, length: range.length), -1,
          levelBuffer.baseAddress, directionBuffer.baseAddress)
      }
    }
    return directions
  }
}
