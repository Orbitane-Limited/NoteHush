import AppKit
import CryptoKit
import Foundation

@main
@MainActor
enum DirectionAttributeProbe {
  static func main() throws {
    guard CommandLine.arguments.count == 3,
      let byteCount = Int(CommandLine.arguments[1]), byteCount >= 16,
      byteCount <= 10_485_760,
      ["natural", "rle", "lre"].contains(CommandLine.arguments[2])
    else { throw NSError(domain: "direction", code: 1) }
    let mode = CommandLine.arguments[2]
    let header = "123456789012345\n"
    let unit = "خط📝"
    let text = header + String(repeating: unit, count: (byteCount - 16) / 8)
    guard text.utf8.count == byteCount else { throw NSError(domain: "direction", code: 2) }
    let style = NSMutableParagraphStyle()
    style.baseWritingDirection = .natural
    let mutable = NSMutableAttributedString(
      string: text,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .paragraphStyle: style,
      ])
    if mode != "natural" {
      let value = mode == "rle" ? 1 : 0
      mutable.addAttribute(
        .writingDirection, value: [NSNumber(value: value)],
        range: NSRange(location: 0, length: mutable.length))
    }
    let content = NSTextContentStorage()
    let storage = NSTextStorage(attributedString: mutable)
    content.textStorage = storage
    let layout = NSTextLayoutManager()
    content.addTextLayoutManager(layout)
    content.primaryTextLayoutManager = layout
    layout.textContainer = NSTextContainer(
      size: NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude))
    let started = ContinuousClock.now
    layout.ensureLayout(for: content.documentRange)
    let elapsed = started.duration(to: .now).components
    var coverage = 0
    var lineCount = 0
    var rows: [String] = []
    _ = layout.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
      for line in fragment.textLineFragments {
        coverage += line.characterRange.length
        lineCount += 1
        rows.append(
          "\(line.characterRange.location):\(line.characterRange.length):\(line.typographicBounds.width.bitPattern)"
        )
      }
      return true
    }
    let digest = SHA256.hash(data: Data(rows.joined(separator: ";").utf8)).map {
      String(format: "%02x", $0)
    }.joined()
    print(
      "mode=\(mode) bytes=\(storage.string.utf8.count) utf16=\(storage.length) ns=\(elapsed.seconds * 1_000_000_000 + elapsed.attoseconds / 1_000_000_000) lines=\(lineCount) coverage=\(coverage) exactText=\(storage.string == text) geometry=\(digest)"
    )
  }
}
