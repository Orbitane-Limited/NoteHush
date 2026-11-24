import AppKit
import CryptoKit
import Foundation

func run(byteCount: Int, wrapMode: String) throws -> [String: Any] {
  let unit = "خط📝"
  let header = "123456789012345\n"
  let repetitions = (byteCount - header.utf8.count) / unit.utf8.count
  let text = header + String(repeating: unit, count: repetitions)
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  style.lineBreakMode = wrapMode == "character" ? .byCharWrapping : .byWordWrapping
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let storage = NSTextStorage(
    string: text,
    attributes: [.font: font, .paragraphStyle: style])
  let layout = NSLayoutManager()
  layout.allowsNonContiguousLayout = true
  layout.backgroundLayoutEnabled = false
  layout.usesDefaultHyphenation = false
  storage.addLayoutManager(layout)
  let container = NSTextContainer(
    size: NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude))
  container.widthTracksTextView = true
  layout.addTextContainer(container)

  layout.ensureLayout(for: container)
  let glyphRange = layout.glyphRange(for: container)
  var actualGlyphRange = NSRange(location: NSNotFound, length: 0)
  let characterRange = layout.characterRange(
    forGlyphRange: glyphRange, actualGlyphRange: &actualGlyphRange)
  var lineCount = 0
  var geometry = ""
  layout.enumerateLineFragments(forGlyphRange: glyphRange) {
    lineRect, usedRect, _, lineGlyphRange, _ in
    lineCount += 1
    let lineCharacters = layout.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
    geometry +=
      "\(lineCharacters.location):\(lineCharacters.length):\(usedRect.width.bitPattern):\(lineRect.height.bitPattern);"
  }
  let digest = SHA256.hash(data: Data(geometry.utf8)).map { String(format: "%02x", $0) }.joined()
  return [
    "requestedUTF8Bytes": byteCount,
    "actualUTF8Bytes": text.utf8.count,
    "sourceUTF16": storage.length,
    "wrapMode": wrapMode,
    "glyphCount": layout.numberOfGlyphs,
    "containerGlyphRange": [glyphRange.location, glyphRange.length],
    "actualGlyphRange": [actualGlyphRange.location, actualGlyphRange.length],
    "containerCharacterRange": [characterRange.location, characterRange.length],
    "completeCharacterCoverage": characterRange.location == 0
      && characterRange.length == storage.length,
    "lineCount": lineCount,
    "geometrySHA256": digest,
  ]
}

let args = Array(CommandLine.arguments.dropFirst())
let result = try run(
  byteCount: Int(args.first ?? "10485760") ?? 10_485_760,
  wrapMode: args.dropFirst().first ?? "word")
print(
  String(
    decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
    as: UTF8.self))
