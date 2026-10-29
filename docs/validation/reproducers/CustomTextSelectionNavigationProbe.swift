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
  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? ProbeLocation else { return false }
    return offset == other.offset
  }
  override var hash: Int { offset }
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

final class ChunkManager: NSTextContentManager, NSTextSelectionDataSource {
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
  func enumerateSubstrings(
    from location: any NSTextLocation, options: NSString.EnumerationOptions = [],
    using block: (String?, NSTextRange, NSTextRange?, UnsafeMutablePointer<ObjCBool>) -> Void
  ) {
    guard let start = location as? ProbeLocation else { return }
    let text = source.string as NSString
    let lower = max(0, min(text.length, start.offset))
    let range =
      options.contains(.reverse)
      ? NSRange(location: 0, length: lower) : NSRange(location: lower, length: text.length - lower)
    var values: [(String?, NSRange, NSRange)] = []
    text.enumerateSubstrings(in: range, options: options) { value, subrange, enclosing, _ in
      values.append((value, subrange, enclosing))
    }
    for (value, subrange, enclosing) in values {
      let textRange = NSTextRange(
        location: ProbeLocation(subrange.location), end: ProbeLocation(NSMaxRange(subrange)))!
      let enclosingRange = NSTextRange(
        location: ProbeLocation(enclosing.location), end: ProbeLocation(NSMaxRange(enclosing)))!
      var stop = ObjCBool(false)
      withUnsafeMutablePointer(to: &stop) { block(value, textRange, enclosingRange, $0) }
      if stop.boolValue { break }
    }
  }
  func textRange(
    for selectionGranularity: NSTextSelection.Granularity, enclosing location: any NSTextLocation
  ) -> NSTextRange? {
    guard let position = location as? ProbeLocation else { return nil }
    if source.length == 0 { return nil }
    let ns = source.string as NSString
    let index = min(max(0, position.offset), ns.length - 1)
    let range: NSRange
    switch selectionGranularity {
    case .character: range = ns.rangeOfComposedCharacterSequence(at: index)
    case .word:
      var match = NSRange(location: index, length: 0)
      ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) {
        _, candidate, _, stop in
        if NSLocationInRange(index, candidate) {
          match = candidate
          stop.pointee = true
        }
      }
      range = match
    case .paragraph: range = ns.paragraphRange(for: NSRange(location: index, length: 0))
    case .line: range = ns.lineRange(for: NSRange(location: index, length: 0))
    case .sentence: range = ns.rangeOfComposedCharacterSequence(at: index)
    @unknown default: range = NSRange(location: index, length: 1)
    }
    return NSTextRange(
      location: ProbeLocation(range.location), end: ProbeLocation(NSMaxRange(range)))
  }
  func baseWritingDirection(at location: any NSTextLocation)
    -> NSTextSelectionNavigation.WritingDirection
  { .leftToRight }
  func enumerateCaretOffsetsInLineFragment(
    at location: any NSTextLocation,
    using block: (CGFloat, any NSTextLocation, Bool, UnsafeMutablePointer<ObjCBool>) -> Void
  ) {
    block(0, location, true, UnsafeMutablePointer<ObjCBool>.allocate(capacity: 1))
  }
  func lineFragmentRange(for point: CGPoint, inContainerAt location: any NSTextLocation)
    -> NSTextRange?
  { nil }
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
  let navigation = NSTextSelectionNavigation(dataSource: manager)
  let initial = NSTextSelection(ProbeLocation(0), affinity: .downstream)
  guard
    let documentEnd = navigation.destinationSelection(
      for: initial, direction: .forward, destination: .document, extending: false, confined: false
    )?.textRanges.first?.endLocation as? ProbeLocation,
    let nextCharacter = navigation.destinationSelection(
      for: initial, direction: .forward, destination: .character, extending: false, confined: false
    )?.textRanges.first?.endLocation as? ProbeLocation
  else { throw NSError(domain: "navigation", code: 1) }
  let ns = source.string as NSString
  let expectedFirst = NSMaxRange(ns.rangeOfComposedCharacterSequence(at: 0))
  guard documentEnd.offset == source.length, nextCharacter.offset == expectedFirst else {
    throw NSError(domain: "navigation", code: 2)
  }
  guard
    let extended = navigation.destinationSelection(
      for: initial, direction: .forward, destination: .character, extending: true, confined: false
    )?.textRanges.first,
    (extended.location as? ProbeLocation)?.offset == 0,
    (extended.endLocation as? ProbeLocation)?.offset == expectedFirst
  else { throw NSError(domain: "navigation", code: 7) }
  guard
    let lastBackward = navigation.destinationSelection(
      for: NSTextSelection(ProbeLocation(source.length), affinity: .upstream),
      direction: .backward, destination: .character, extending: false, confined: false
    )?.textRanges.first?.location as? ProbeLocation
  else { throw NSError(domain: "navigation", code: 3) }
  let expectedLast = ns.rangeOfComposedCharacterSequence(at: ns.length - 1).location
  guard lastBackward.offset == expectedLast else { throw NSError(domain: "navigation", code: 4) }
  if name == "rtl-emoji" {
    let emojiStart = 2
    let expectedEmojiEnd = NSMaxRange(ns.rangeOfComposedCharacterSequence(at: emojiStart))
    guard
      let emojiEnd = navigation.destinationSelection(
        for: NSTextSelection(ProbeLocation(emojiStart), affinity: .downstream),
        direction: .forward, destination: .character, extending: false, confined: false
      )?.textRanges.first?.endLocation as? ProbeLocation,
      emojiEnd.offset == expectedEmojiEnd
    else { throw NSError(domain: "navigation", code: 5) }
  }
  for boundary in chunks.dropFirst().map(\.0) {
    let previousRange = ns.rangeOfComposedCharacterSequence(at: boundary - 1)
    guard NSMaxRange(previousRange) == boundary,
      let forward = navigation.destinationSelection(
        for: NSTextSelection(ProbeLocation(boundary - 1), affinity: .downstream),
        direction: .forward, destination: .character, extending: false, confined: false
      )?.textRanges.first?.endLocation as? ProbeLocation,
      forward.offset == boundary,
      let backward = navigation.destinationSelection(
        for: NSTextSelection(ProbeLocation(boundary), affinity: .downstream),
        direction: .backward, destination: .character, extending: false, confined: false
      )?.textRanges.first?.location as? ProbeLocation,
      backward.offset == previousRange.location
    else { throw NSError(domain: "navigation", code: 8) }
  }
  let paragraph = manager.textRange(for: .paragraph, enclosing: ProbeLocation(source.length / 2))
  guard let paragraph, manager.offset(from: paragraph.location, to: paragraph.endLocation) > 0
  else {
    throw NSError(domain: "navigation", code: 6)
  }
  print(
    "navigation case=\(name) documentEnd=\(documentEnd.offset) firstGraphemeEnd=\(nextCharacter.offset) lastGraphemeStart=\(lastBackward.offset) paragraphSelection=passed"
  )
  let layout = NSTextLayoutManager()
  manager.addTextLayoutManager(layout)
  manager.primaryTextLayoutManager = layout
  layout.textContainer = NSTextContainer(
    size: NSSize(width: 858, height: CGFloat.greatestFiniteMagnitude))
  let range = manager.documentRange
  layout.ensureLayout(for: range)
  var fragmentsSeen = 0
  _ = layout.enumerateTextLayoutFragments(from: range.location, options: [.ensuresLayout]) {
    fragment in
    fragmentsSeen += 1
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
    "managerAttached=\(layout.textContentManager === manager) fragments=\(fragmentsSeen) emitted=\(manager.emitted) case=\(name) utf16=\(source.length) chunks=\(chunks.count) nativeLines=\(original.count) customManagerLines=\(actual.count) exact=\(exact) firstDiff=\(String(describing: diff))"
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
