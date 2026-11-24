import AppKit
import CoreText
import CryptoKit
import Foundation

func digest(_ ranges: [(Int, Int)]) -> String {
  let value = ranges.map { "\($0.0):\($0.1)" }.joined(separator: ";")
  return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

@MainActor
func runCase(_ label: String, text: String) throws {
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let paragraph = NSMutableParagraphStyle()
  paragraph.baseWritingDirection = .natural
  let source = NSAttributedString(
    string: text, attributes: [.font: font, .paragraphStyle: paragraph])
  let view = NSTextView(usingTextLayoutManager: true)
  view.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
  view.isRichText = false
  view.font = font
  view.textContainerInset = NSSize(width: 16, height: 16)
  view.isVerticallyResizable = true
  view.isHorizontallyResizable = false
  guard let storage = view.textStorage, let container = view.textContainer,
    let layout = view.textLayoutManager
  else {
    throw NSError(domain: "geometry-calibration", code: 1)
  }
  container.widthTracksTextView = true
  container.containerSize = NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude)
  storage.setAttributedString(source)
  guard
    let range = NSTextRange(
      location: layout.documentRange.location, end: layout.documentRange.endLocation)
  else {
    throw NSError(domain: "geometry-calibration", code: 2)
  }
  layout.ensureLayout(for: range)
  var native: [(Int, Int)] = []
  _ = layout.enumerateTextLayoutFragments(from: range.location, options: []) { fragment in
    for line in fragment.textLineFragments {
      native.append((line.characterRange.location, line.characterRange.length))
    }
    return true
  }

  // App container width is 868 points. NSTextContainer's default 5-point padding
  // on each side gives the editor and Core Text 858 points of line width.
  let typesetter = CTTypesetterCreateWithAttributedString(source as CFAttributedString)
  var core: [(Int, Int)] = []
  var start = 0
  while start < source.length {
    let count = CTTypesetterSuggestLineBreak(typesetter, start, 858)
    guard count > 0 else { throw NSError(domain: "geometry-calibration", code: 3) }
    core.append((start, count))
    start += count
  }
  let exact = native.elementsEqual(core) { $0.0 == $1.0 && $0.1 == $1.1 }
  print(
    "case=\(label) utf8=\(text.utf8.count) utf16=\(source.length) nativeLines=\(native.count) coreTextLines=\(core.count) exactRanges=\(exact) nativeSHA256=\(digest(native)) coreTextSHA256=\(digest(core)) nativeFirst=\(native.prefix(2)) coreTextFirst=\(core.prefix(2))"
  )
}

@main @MainActor enum Main {
  static func main() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    try runCase("rtl-emoji", text: String(repeating: "خط📝", count: 2_000))
    try runCase("mixed-latin-numbers", text: String(repeating: "abc اردو 123 — שלום🙂 ", count: 500))
    try runCase(
      "combining-rtl", text: String(repeating: "e\u{301} العربية العربية אבג 🧑🏽‍💻 ", count: 500))
    try runCase(
      "punctuation-parens", text: String(repeating: "(rtl: العربية 42) [עברית, 7] — 🙂 ", count: 500)
    )
  }
}
