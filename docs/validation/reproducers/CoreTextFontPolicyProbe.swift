import AppKit
import CoreText

// Separate, generated public-API hypotheses. Never linked into NoteHush.
@main
@MainActor
enum CoreTextFontPolicyProbe {
  static func record(_ value: [String: Any]) throws {
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: value) + Data([10]))
  }

  static func main() throws {
    guard CommandLine.arguments.count == 3,
      let bytes = Int(CommandLine.arguments[1]), [262_144, 1_048_576].contains(bytes),
      ["fixFonts", "arabicBase", "arabicOnly", "emojiOnly"].contains(CommandLine.arguments[2])
    else { exit(64) }
    let variant = CommandLine.arguments[2]
    let unit = variant == "arabicOnly" ? "خط" : variant == "emojiOnly" ? "📝" : "خط📝"
    let text = String(repeating: unit, count: bytes / unit.utf8.count)
    let font: NSFont
    if variant == "arabicBase" {
      guard let available = NSFont(name: "GeezaPro", size: 14) else {
        try record(["phase": "requiredFontUnavailable"])
        exit(65)
      }
      font = available
    } else {
      font = .monospacedSystemFont(ofSize: 14, weight: .regular)
    }
    let attributed = NSMutableAttributedString(string: text, attributes: [.font: font])
    try record(["phase": "beforeFontPreparation", "variant": variant, "bytes": bytes,
                "utf16": attributed.length])
    if variant == "fixFonts" {
      attributed.fixFontAttribute(in: NSRange(location: 0, length: attributed.length))
    }
    guard attributed.string.utf8.elementsEqual(text.utf8) else { exit(66) }
    try record(["phase": "beforeTypesetter", "exactText": true])
    let options = [kCTTypesetterOptionAllowUnboundedLayout as String: true] as CFDictionary
    guard let typesetter = CTTypesetterCreateWithAttributedStringAndOptions(attributed, options) else {
      try record(["phase": "typesetterDeclined"])
      exit(67)
    }
    try record(["phase": "typesetterCreated"])
    let count = CTTypesetterSuggestLineBreak(typesetter, 0, 800)
    guard count > 0, count <= attributed.length else { exit(68) }
    let line = CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: count))
    guard CTLineGetStringRange(line).location == 0,
      CTLineGetStringRange(line).length == count, CTLineGetGlyphCount(line) > 0
    else { exit(69) }
    try record(["phase": "firstLineAvailable", "coveredUTF16": count, "exactText": true,
                "wholeParagraphRenderingVerified": false])
    withExtendedLifetime((attributed, typesetter, line)) {}
  }
}
