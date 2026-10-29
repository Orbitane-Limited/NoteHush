import AppKit
import CoreText
import Foundation

@MainActor struct ShapedLine: Equatable { let start: Int; let length: Int; let width: UInt }

@MainActor func nativeLines(_ source: NSAttributedString, width: CGFloat) throws -> [ShapedLine] {
  let content = NSTextContentStorage()
  let backing = NSTextStorage(attributedString: source)
  content.textStorage = backing
  let manager = NSTextLayoutManager()
  content.addTextLayoutManager(manager)
  content.primaryTextLayoutManager = manager
  manager.textContainer = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
  manager.ensureLayout(for: manager.documentRange)
  var rows: [ShapedLine] = []
  _ = manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: []) { fragment in
    guard let range = fragment.textElement?.elementRange else { return false }
    let base = content.offset(from: content.documentRange.location, to: range.location)
    for line in fragment.textLineFragments {
      rows.append(ShapedLine(start: base + line.characterRange.location, length: line.characterRange.length, width: line.typographicBounds.width.bitPattern))
    }
    return true
  }
  return rows
}

@MainActor func plannedLines(_ source: NSAttributedString, width: Double, cap: Int) throws -> [ShapedLine] {
  var result: [ShapedLine] = []
  var start = 0
  while start < source.length {
    let length = min(cap, source.length - start)
    let candidate = source.attributedSubstring(from: NSRange(location: start, length: length))
    let typesetter = CTTypesetterCreateWithAttributedString(candidate as CFAttributedString)
    var local: [ShapedLine] = []
    var lineStart = 0
    while lineStart < candidate.length {
      let count = CTTypesetterSuggestLineBreak(typesetter, lineStart, width)
      guard count > 0 else { throw NSError(domain: "probe", code: 1) }
      let line = CTTypesetterCreateLine(typesetter, CFRange(location: lineStart, length: count))
      let typographicWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
      local.append(ShapedLine(start: start + lineStart, length: count, width: CGFloat(typographicWidth).bitPattern))
      lineStart += count
    }
    if start + length < source.length && local.count > 1 {
      result.append(contentsOf: local.dropLast())
      start += local[local.count - 2].start + local[local.count - 2].length - start
    } else {
      result.append(contentsOf: local)
      start += length
    }
  }
  return result
}

@MainActor func fixture(_ name: String, _ string: String, cap: Int) throws {
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let source = NSAttributedString(string: string, attributes: [.font: font, .paragraphStyle: style])
  let native = try nativeLines(source, width: 868)
  let plan = try plannedLines(source, width: 858, cap: cap)
  let first = zip(native, plan).enumerated().first { $0.element.0 != $0.element.1 }
  let boundariesMatch = native.count == plan.count
    && zip(native, plan).allSatisfy { $0.start == $1.start && $0.length == $1.length }
  let widthMismatches = zip(native, plan).filter { $0.width != $1.width }.count
  print("name=\(name) units=\(source.length) native=\(native.count) planned=\(plan.count) boundariesMatch=\(boundariesMatch) widthMismatches=\(widthMismatches) exact=\(native == plan) firstDiff=\(String(describing: first))")
}

@main @MainActor enum Main {
  static func main() async throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let fixtures: [(String,String)] = [
      ("rtl-emoji", String(repeating: "خط📝", count: 2000)),
      ("mixed-latin-numbers", String(repeating: "abc اردو 123 — שלום🙂 ", count: 500)),
      ("combining-rtl", String(repeating: "e\u{301} العربية العربية אבג 🧑🏽‍💻 ", count: 500)),
      ("punctuation-parens", String(repeating: "(rtl: العربية 42) [עברית, 7] — 🙂 ", count: 500)),
    ]
    for cap in [4096, 16384] {
      for (name, text) in fixtures { try fixture(name, text, cap: cap) }
    }
    let text = String(repeating: "خط📝", count: 1_310_720)
    let style = NSMutableParagraphStyle(); style.baseWritingDirection = .natural
    let source = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .paragraphStyle: style])
    for cap in [16384, 65536] {
      let started = ContinuousClock.now
      let lines = try plannedLines(source, width: 858, cap: cap)
      print("large_cap=\(cap) units=\(source.length) rows=\(lines.count) coverage=\(lines.reduce(0){$0+$1.length}) elapsed=\(started.duration(to: .now))")
    }
  }
}
