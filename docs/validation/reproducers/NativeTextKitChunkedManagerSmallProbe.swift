import AppKit
import Foundation

final class ProbeLocation: NSObject, NSTextLocation {
  let offset: Int
  init(_ offset: Int) { self.offset = offset }
  func compare(_ other: any NSTextLocation) -> ComparisonResult {
    guard let value = other as? ProbeLocation else { return .orderedSame }
    if offset < value.offset { return .orderedAscending }
    if offset > value.offset { return .orderedDescending }
    return .orderedSame
  }
}

@MainActor final class Planner {
  private let storage = NSTextContentStorage()
  private let backing = NSTextStorage()
  private let layout = NSTextLayoutManager()
  init() {
    storage.textStorage = backing
    storage.addTextLayoutManager(layout)
    storage.primaryTextLayoutManager = layout
    layout.textContainer = NSTextContainer(
      size: NSSize(width: 858, height: CGFloat.greatestFiniteMagnitude))
  }
  func lines(_ value: NSAttributedString) throws -> [(Int, Int, UInt)] {
    backing.setAttributedString(value)
    let doc = storage.documentRange
    let range = NSTextRange(location: doc.location, end: doc.endLocation)!
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

final class ChunkManager: NSTextContentManager {
  private(set) var emitted = 0
  let source: NSAttributedString
  let ranges: [(Int, Int)]
  init(source: NSAttributedString, ranges: [(Int, Int)]) {
    self.source = source
    self.ranges = ranges
    super.init()
  }
  required init?(coder: NSCoder) { nil }
  override var documentRange: NSTextRange {
    NSTextRange(location: ProbeLocation(0), end: ProbeLocation(source.length))!
  }
  override func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (
    any NSTextLocation
  )? {
    guard let value = location as? ProbeLocation else { return nil }
    let next = value.offset + offset
    guard (0...source.length).contains(next) else { return nil }
    return ProbeLocation(next)
  }
  override func offset(from: any NSTextLocation, to: any NSTextLocation) -> Int {
    guard let a = from as? ProbeLocation, let b = to as? ProbeLocation else { return NSNotFound }
    return b.offset - a.offset
  }
  override func enumerateTextElements(
    from location: (any NSTextLocation)?, options: NSTextContentManager.EnumerationOptions,
    using block: (NSTextElement) -> Bool
  ) -> (any NSTextLocation)? {
    let reverse = options.contains(.reverse)
    let offset = (location as? ProbeLocation)?.offset ?? (reverse ? source.length : 0)
    let candidates = reverse ? Array(ranges.reversed()) : ranges
    var last = ProbeLocation(offset)
    for (start, end) in candidates where (reverse ? end <= offset : end > offset) {
      let paragraph = NSTextParagraph(
        attributedString: source.attributedSubstring(
          from: NSRange(location: start, length: end - start)))
      paragraph.textContentManager = self
      emitted += 1
      paragraph.elementRange = NSTextRange(location: ProbeLocation(start), end: ProbeLocation(end))!
      let boundary = reverse ? start : end
      last = ProbeLocation(boundary)
      if !block(paragraph) { return last }
    }
    return last
  }
}

@MainActor func run(_ name: String, _ text: String) throws {
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let source = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
  let original = try Planner().lines(source)
  var chunks: [(Int, Int)] = []
  var start = 0
  for line in original {
    let end = line.0 + line.1
    if end - start >= 4096 {
      chunks.append((start, end))
      start = end
    }
  }
  if start < source.length { chunks.append((start, source.length)) }
  let manager = ChunkManager(source: source, ranges: chunks)
  let layout = NSTextLayoutManager()
  manager.addTextLayoutManager(layout)
  manager.primaryTextLayoutManager = layout
  layout.textContainer = NSTextContainer(
    size: NSSize(width: 858, height: CGFloat.greatestFiniteMagnitude))
  let range = manager.documentRange
  layout.ensureLayout(for: range)
  var fragmentsSeen = 0
  var fragmentNotes: [String] = []
  _ = layout.enumerateTextLayoutFragments(from: range.location, options: [.ensuresLayout]) {
    fragment in
    fragmentsSeen += 1
    fragmentNotes.append(
      "\(type(of: fragment)) state=\(fragment.state.rawValue) lines=\(fragment.textLineFragments.count) range=\(String(describing: fragment.textElement?.elementRange))"
    )
    return true
  }
  var actual: [(Int, Int, UInt)] = []
  _ = layout.enumerateTextLayoutFragments(from: range.location, options: [.ensuresLayout]) {
    fragment in
    guard let elementRange = fragment.textElement?.elementRange else { return false }
    let base = manager.offset(from: manager.documentRange.location, to: elementRange.location)
    for line in fragment.textLineFragments {
      actual.append(
        (
          base + line.characterRange.location, line.characterRange.length,
          line.typographicBounds.width.bitPattern
        ))
    }
    return true
  }
  let exact =
    original.count == actual.count
    && zip(original, actual).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
  let diff = zip(original, actual).enumerated().first { $0.element.0 != $0.element.1 }
  print(
    "notes=\(fragmentNotes) managerAttached=\(layout.textContentManager === manager) fragments=\(fragmentsSeen) emitted=\(manager.emitted) case=\(name) utf16=\(source.length) chunks=\(chunks.count) nativeLines=\(original.count) customManagerLines=\(actual.count) exact=\(exact) firstDiff=\(String(describing: diff))"
  )
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
