import AppKit
import Foundation

@MainActor
final class Shaper {
  private let storage = NSTextContentStorage()
  private let backing = NSTextStorage()
  private let layout = NSTextLayoutManager()
  init(width: CGFloat = 858) {
    storage.textStorage = backing
    storage.addTextLayoutManager(layout)
    storage.primaryTextLayoutManager = layout
    layout.textContainer = NSTextContainer(
      size: NSSize(width: width, height: .greatestFiniteMagnitude))
  }
  func lines(_ value: NSAttributedString) throws -> [(Int, Int, UInt)] {
    backing.setAttributedString(value)
    let doc = storage.documentRange
    guard let range = NSTextRange(location: doc.location, end: doc.endLocation) else {
      throw NSError(domain: "probe", code: 1)
    }
    layout.ensureLayout(for: range)
    var result: [(Int, Int, UInt)] = []
    _ = layout.enumerateTextLayoutFragments(from: range.location, options: []) { fragment in
      guard let elementRange = fragment.textElement?.elementRange else { return false }
      let base = storage.offset(from: storage.documentRange.location, to: elementRange.location)
      for line in fragment.textLineFragments {
        result.append(
          (
            base + line.characterRange.location, line.characterRange.length,
            line.typographicBounds.width.bitPattern
          ))
      }
      return true
    }
    return result
  }
}

@MainActor
func run(_ name: String, _ text: String) throws {
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let source = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
  let shaper = Shaper()
  let base = try shaper.lines(source)
  for separator in ["\n", "\u{2028}"] {
    let out = NSMutableString()
    let src = text as NSString
    var pos = 0
    for row in base {
      let len = row.1
      out.append(src.substring(with: NSRange(location: pos, length: len)))
      pos += len
      if pos < src.length { out.append(separator) }
    }
    let split = NSAttributedString(
      string: out as String, attributes: [.font: font, .paragraphStyle: style])
    let splitLines = try shaper.lines(split)
    var mapped: [(Int, Int, UInt)] = []
    var logicalOffset = 0
    for row in splitLines {
      let physical = (out as String as NSString).substring(
        with: NSRange(location: row.0, length: row.1))
      let clean = physical.replacingOccurrences(of: separator, with: "")
      let n = (clean as NSString).length
      if n > 0 {
        mapped.append((logicalOffset, n, row.2))
        logicalOffset += n
      }
    }
    let exact =
      base.count == mapped.count
      && zip(base, mapped).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
    print(
      "case=\(name) separator=\(separator == "\n" ? "LF" : "LS") sourceLines=\(base.count) splitLines=\(mapped.count) exact=\(exact) firstDiff=\(String(describing: zip(base,mapped).enumerated().first { $0.element.0 != $0.element.1 }))"
    )
  }
}

@main @MainActor enum Main {
  static func main() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    try run("rtl-emoji", String(repeating: "خط📝", count: 2000))
    try run("mixed", String(repeating: "abc اردو 123 — שלום🙂 ", count: 500))
    try run("combining", String(repeating: "e\u{301} العربية العربية אבג 🧑🏽‍💻 ", count: 500))
    try run("punctuation", String(repeating: "(rtl: العربية 42) [עברית, 7] — 🙂 ", count: 500))
  }
}
