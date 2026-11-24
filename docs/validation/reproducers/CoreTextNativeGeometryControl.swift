import AppKit
import CoreText
import CryptoKit
import Foundation

func digest(_ rows: [String]) -> String {
  SHA256.hash(data: Data(rows.joined(separator: ";").utf8)).map {
    String(format: "%02x", $0)
  }.joined()
}

func runCase(_ label: String, _ text: String) throws {
  let paragraph = NSMutableParagraphStyle()
  paragraph.baseWritingDirection = .natural
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let source = NSAttributedString(
    string: text, attributes: [.font: font, .paragraphStyle: paragraph])

  let storage = NSTextContentStorage()
  storage.textStorage = NSTextStorage(attributedString: source)
  let layout = NSTextLayoutManager()
  storage.addTextLayoutManager(layout)
  storage.primaryTextLayoutManager = layout
  let container = NSTextContainer(
    size: NSSize(width: 858, height: CGFloat.greatestFiniteMagnitude))
  layout.textContainer = container
  guard
    let range = NSTextRange(
      location: storage.documentRange.location, end: storage.documentRange.endLocation)
  else {
    throw NSError(domain: "geometry", code: 1)
  }
  layout.ensureLayout(for: range)
  var native: [String] = []
  _ = layout.enumerateTextLayoutFragments(from: range.location, options: []) { fragment in
    guard let elementRange = fragment.textElement?.elementRange else { return false }
    let elementOffset = elementRange.location
    let offset = storage.offset(from: storage.documentRange.location, to: elementOffset)
    for line in fragment.textLineFragments {
      native.append(
        "\(offset + line.characterRange.location):\(line.characterRange.length):\(line.typographicBounds.width.bitPattern)"
      )
    }
    return true
  }

  let typesetter = CTTypesetterCreateWithAttributedString(source as CFAttributedString)
  var coreText: [String] = []
  var start = 0
  while start < source.length {
    let count = CTTypesetterSuggestLineBreak(typesetter, start, 858)
    guard count > 0 else { throw NSError(domain: "geometry", code: 2) }
    let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    coreText.append("\(start):\(count):\(Double(width).bitPattern)")
    start += count
  }
  let linesEqual = native == coreText
  print(
    "case=\(label) utf8=\(text.utf8.count) utf16=\(source.length) nativeLines=\(native.count) coreTextLines=\(coreText.count) exactLines=\(linesEqual) native=\(digest(native)) coretext=\(digest(coreText))"
  )
  if !linesEqual {
    print("nativeFirst=\(native.prefix(3)) coreTextFirst=\(coreText.prefix(3))")
  }
}

@MainActor
func main() throws {
  try runCase("rtl-emoji", String(repeating: "خط📝", count: 2_000))
  try runCase("mixed-latin-numbers", String(repeating: "abc اردو 123 — שלום🙂 ", count: 500))
  try runCase("combining-rtl", String(repeating: "e\u{301} العربية العربية אבג 🧑🏽‍💻 ", count: 500))
  try runCase(
    "punctuation-parens", String(repeating: "(rtl: العربية 42) [עברית, 7] — 🙂 ", count: 500))
}

try await MainActor.run { try main() }
