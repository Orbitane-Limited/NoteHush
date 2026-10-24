import AppKit
import CoreFoundation

@MainActor
final class ParagraphDirectionPresenter: NSObject, @MainActor NSTextContentStorageDelegate {
  // Resolve presentation only. Native TextKit remains responsible for shaping,
  // selection and editing; the backing text and its paragraph styles stay intact.
  func textContentStorage(_ content: NSTextContentStorage, textParagraphWith range: NSRange)
    -> NSTextParagraph?
  {
    precondition(Thread.isMainThread)
    // Bound transient direction buffers to two MiB. Larger paragraphs and older
    // systems retain standard native presentation, including all Unicode behavior.
    guard #available(macOS 26.0, *), range.length > 0, range.length <= 1_048_576,
      let storage = content.textStorage, range.location >= 0,
      range.location <= storage.length, range.length <= storage.length - range.location
    else { return nil }
    let original = storage.attributedSubstring(from: range)
    let style =
      original.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
      ?? .default
    guard style.baseWritingDirection == .natural else { return nil }
    var uniformStyle = true
    original.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: original.length))
    { value, _, stop in
      let candidate = value as? NSParagraphStyle ?? .default
      if !candidate.isEqual(style) {
        uniformStyle = false
        stop.pointee = true
      }
    }
    guard uniformStyle else { return nil }
    var levels = [UInt8](repeating: 253, count: range.length)
    var directions = [UInt8](repeating: 253, count: range.length)
    let attributed = original as CFAttributedString
    let count = range.length
    levels.withUnsafeMutableBufferPointer { levelBuffer in
      directions.withUnsafeMutableBufferPointer { directionBuffer in
        _ = CFAttributedStringGetStatisticalWritingDirections(
          attributed,
          CFRange(location: 0, length: count), -1, levelBuffer.baseAddress,
          directionBuffer.baseAddress)
      }
    }
    guard let base = directions.first, base == 0 || base == 1,
      directions.allSatisfy({ $0 == base }),
      let resolved = style.mutableCopy() as? NSMutableParagraphStyle
    else { return nil }
    resolved.baseWritingDirection = base == 0 ? .leftToRight : .rightToLeft
    let presented = NSMutableAttributedString(attributedString: original)
    presented.addAttribute(
      .paragraphStyle, value: resolved, range: NSRange(location: 0, length: count))
    precondition(presented.length == count && presented.string == original.string)
    return NSTextParagraph(attributedString: presented)
  }
}
