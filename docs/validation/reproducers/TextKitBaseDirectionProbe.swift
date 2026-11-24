import AppKit
import CryptoKit
import Foundation

@MainActor
final class DirectionPresenter: NSObject, @MainActor NSTextContentStorageDelegate {
  func textContentStorage(_ content: NSTextContentStorage, textParagraphWith range: NSRange)
    -> NSTextParagraph?
  {
    guard let storage = content.textStorage else { return nil }
    let original = storage.attributedSubstring(from: range)
    let style =
      (original.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?
      .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
    style.baseWritingDirection = .rightToLeft
    let presented = NSMutableAttributedString(attributedString: original)
    presented.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: range.length))
    return NSTextParagraph(attributedString: presented)
  }
}

@main
@MainActor
enum Probe {
  static func main() throws {
    guard CommandLine.arguments.count == 3,
      let byteCount = Int(CommandLine.arguments[1]), byteCount >= 16,
      byteCount <= 10_485_760, byteCount.isMultiple(of: 8),
      ["natural", "rtl"].contains(CommandLine.arguments[2]) else { exit(EX_CONFIG) }
    let mode = CommandLine.arguments[2]
    let header = "123456789012345\n"
    let unit = "خط📝"
    let text = header + String(repeating: unit, count: (byteCount - 16) / 8)
    let style = NSMutableParagraphStyle()
    style.baseWritingDirection = .natural
    let source = NSAttributedString(
      string: text,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
        .paragraphStyle: style,
      ])
    let content = NSTextContentStorage()
    let storage = NSTextStorage(attributedString: source)
    content.textStorage = storage
    let presenter = DirectionPresenter()
    if mode == "rtl" { content.delegate = presenter }
    let layout = NSTextLayoutManager()
    content.addTextLayoutManager(layout)
    content.primaryTextLayoutManager = layout
    layout.textContainer = NSTextContainer(
      size: NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude))
    let started = ContinuousClock.now
    layout.ensureLayout(for: content.documentRange)
    let elapsed = started.duration(to: .now)
    var lineCount = 0
    var coverage = 0
    var rows: [String] = []
    _ = layout.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
      for line in fragment.textLineFragments {
        lineCount += 1
        coverage += line.characterRange.length
        rows.append("\(line.characterRange.location):\(line.characterRange.length):\(line.typographicBounds.width.bitPattern)")
      }
      return true
    }
    let digest = SHA256.hash(data: Data(rows.joined(separator: ";").utf8)).map {
      String(format: "%02x", $0)
    }.joined()
    let parts = elapsed.components
    let elapsedNanoseconds = UInt64(parts.seconds) * 1_000_000_000
      + UInt64(parts.attoseconds / 1_000_000_000)
    print("mode=\(mode) bytes=\(text.utf8.count) utf16=\(storage.length) elapsed_ns=\(elapsedNanoseconds) lines=\(lineCount) coverage=\(coverage) exact_text=\(storage.string == text) geometry_sha256=\(digest)")
  }
}
