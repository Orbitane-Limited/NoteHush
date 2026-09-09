import AppKit
import CoreText

// Generated, standalone diagnosis only. No editor code or user text is involved.
@main
@MainActor
enum CoreTextFallbackProbe {
  static func record(_ value: [String: Any]) throws {
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: value) + Data([10]))
  }

  static func main() throws {
    guard CommandLine.arguments.count == 3,
      let bytes = Int(CommandLine.arguments[1]),
      [16_384, 262_144, 1_048_576].contains(bytes),
      ["native", "explicitFallback", "separateAttributes", "chunkedAttributes"].contains(CommandLine.arguments[2])
    else { exit(64) }
    let variant = CommandLine.arguments[2]
    let text = String(repeating: "خط📝", count: bytes / 8)
    let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    let attributed = NSMutableAttributedString(string: text, attributes: [.font: baseFont])
    try record(["phase": "beforeAttributes", "bytes": bytes, "variant": variant])
    if variant == "explicitFallback" {
      let arabic = CTFontCreateForString(baseFont as CTFont, "خط" as CFString, CFRange(location: 0, length: 2))
      let emoji = CTFontCreateForString(baseFont as CTFont, "📝" as CFString, CFRange(location: 0, length: 2))
      for offset in stride(from: 0, to: attributed.length, by: 4) {
        attributed.addAttribute(.font, value: arabic, range: NSRange(location: offset, length: 2))
        attributed.addAttribute(.font, value: emoji, range: NSRange(location: offset + 2, length: 2))
      }
    } else if variant == "separateAttributes" {
      // A private diagnostic attribute separates the attributed-string ranges
      // without changing fonts, direction, paragraph breaks or shaping features.
      let marker = NSAttributedString.Key("NoteHushGeneratedDiagnosticRange")
      for offset in stride(from: 0, to: attributed.length, by: 4) {
        attributed.addAttribute(marker, value: 0, range: NSRange(location: offset, length: 2))
        attributed.addAttribute(marker, value: 1, range: NSRange(location: offset + 2, length: 2))
      }
    } else if variant == "chunkedAttributes" {
      let marker = NSAttributedString.Key("NoteHushGeneratedDiagnosticRange")
      for offset in stride(from: 0, to: attributed.length, by: 4096) {
        attributed.addAttribute(marker, value: offset / 4096,
                                range: NSRange(location: offset, length: min(4096, attributed.length - offset)))
      }
    }
    guard attributed.string.utf8.elementsEqual(text.utf8), attributed.length == bytes / 2 else { exit(65) }
    try record(["phase": "beforeTypesetter", "exactText": true])
    let options = [kCTTypesetterOptionAllowUnboundedLayout as String: true] as CFDictionary
    guard let typesetter = CTTypesetterCreateWithAttributedStringAndOptions(attributed, options) else {
      try record(["phase": "typesetterDeclined"])
      exit(66)
    }
    let count = CTTypesetterSuggestLineBreak(typesetter, 0, 800)
    guard count > 0, count <= attributed.length else { exit(67) }
    let line = CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: count))
    guard CTLineGetStringRange(line).location == 0,
      CTLineGetStringRange(line).length == count,
      CTLineGetGlyphCount(line) > 0
    else { exit(68) }
    try record(["phase": "firstLineAvailable", "coveredUTF16": count, "exactText": true,
                "wholeParagraphRenderingVerified": false])
    withExtendedLifetime((attributed, typesetter, line)) {}
  }
}
