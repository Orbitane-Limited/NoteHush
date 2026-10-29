import AppKit
import CoreFoundation
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

struct ChunkPlan {
  let ranges: [(Int, Int)]
  let lines: [(Int, Int, UInt)]
}

@MainActor final class BoundedNativeShaper {
  private let storage = NSTextContentStorage()
  private let backing = NSTextStorage()
  private let layout = NSTextLayoutManager()
  init(width: CGFloat) {
    storage.textStorage = backing
    storage.addTextLayoutManager(layout)
    storage.primaryTextLayoutManager = layout
    layout.textContainer = NSTextContainer(
      size: NSSize(width: width, height: .greatestFiniteMagnitude))
  }
  func lines(_ attributed: NSAttributedString) throws -> [(Int, Int, UInt)] {
    backing.setAttributedString(attributed)
    guard
      let range = NSTextRange(
        location: storage.documentRange.location, end: storage.documentRange.endLocation)
    else { throw NSError(domain: "probe", code: 1) }
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

@MainActor func planChunks(_ source: NSAttributedString, cap: Int = 4096) async throws
  -> ChunkPlan
{
  var ranges: [(Int, Int)] = []
  var lines: [(Int, Int, UInt)] = []
  var start = 0
  let shaper = BoundedNativeShaper(width: 858)
  while start < source.length {
    let available = min(cap, source.length - start)
    let candidate = source.attributedSubstring(from: NSRange(location: start, length: available))
    let candidateLines = try shaper.lines(candidate)
    var end = start + available
    if end < source.length && candidateLines.count > 1 {
      let previousLine = candidateLines[candidateLines.count - 2]
      end = start + previousLine.0 + previousLine.1
    }
    guard end > start else { throw NSError(domain: "probe", code: 2) }
    let completeLines = end == start + available ? candidateLines : Array(candidateLines.dropLast())
    ranges.append((start, end))
    lines += completeLines.map { (start + $0.0, $0.1, $0.2) }
    start = end
    if ranges.count.isMultiple(of: 100) {
      fputs("planned chunks=\(ranges.count) covered=\(start)\n", stderr)
    }
    await Task.yield()
  }
  return ChunkPlan(ranges: ranges, lines: lines)
}

final class ChunkManager: NSTextContentManager, NSTextSelectionDataSource {
  private(set) var emitted = 0
  let source: NSAttributedString
  let ranges: [(Int, Int)]
  let lineRanges: [(Int, Int)]
  weak var navigationLayout: NSTextLayoutManager?
  private var directionsByParagraphStart: [Int: NSTextSelectionNavigation.WritingDirection] = [:]
  init(source: NSAttributedString, ranges: [(Int, Int)], lineRanges: [(Int, Int)]) {
    self.source = source
    self.ranges = ranges
    self.lineRanges = lineRanges
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
    if options.rawValue & 0xFF == NSString.EnumerationOptions.byLines.rawValue {
      let candidates = options.contains(.reverse) ? Array(lineRanges.reversed()) : lineRanges
      for (lineStart, lineEnd) in candidates
      where options.contains(.reverse) ? lineStart < lower : lineEnd > lower {
        let substring = text.substring(
          with: NSRange(location: lineStart, length: lineEnd - lineStart))
        let range = NSTextRange(
          location: ProbeLocation(lineStart), end: ProbeLocation(lineEnd))!
        var stop = ObjCBool(false)
        withUnsafeMutablePointer(to: &stop) { block(substring, range, range, $0) }
        if stop.boolValue { break }
      }
      return
    }
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
    case .line:
      guard
        let line = lineRanges.first(where: { $0.0 <= index && index < $0.1 })
          ?? lineRanges.last
      else { return nil }
      range = NSRange(location: line.0, length: line.1 - line.0)
    case .sentence: range = ns.rangeOfComposedCharacterSequence(at: index)
    @unknown default: range = NSRange(location: index, length: 1)
    }
    return NSTextRange(
      location: ProbeLocation(range.location), end: ProbeLocation(NSMaxRange(range)))
  }
  func baseWritingDirection(at location: any NSTextLocation)
    -> NSTextSelectionNavigation.WritingDirection
  {
    guard let position = location as? ProbeLocation, source.length > 0 else { return .leftToRight }
    let string = source.string as NSString
    let index = min(max(0, position.offset), string.length - 1)
    let paragraphRange = string.paragraphRange(for: NSRange(location: index, length: 0))
    if let cached = directionsByParagraphStart[paragraphRange.location] { return cached }
    let style =
      source.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
      ?? .default
    let direction: NSTextSelectionNavigation.WritingDirection
    switch style.baseWritingDirection {
    case .leftToRight:
      direction = .leftToRight
    case .rightToLeft:
      direction = .rightToLeft
    default:
      if #available(macOS 26.0, *) {
        let attributed = source.attributedSubstring(from: paragraphRange) as CFAttributedString
        var levels = [UInt8](repeating: 253, count: paragraphRange.length)
        var directions = [UInt8](repeating: 253, count: paragraphRange.length)
        levels.withUnsafeMutableBufferPointer { levelBuffer in
          directions.withUnsafeMutableBufferPointer { directionBuffer in
            _ = CFAttributedStringGetStatisticalWritingDirections(
              attributed, CFRange(location: 0, length: paragraphRange.length), -1,
              levelBuffer.baseAddress, directionBuffer.baseAddress)
          }
        }
        direction = directions.first == 1 ? .rightToLeft : .leftToRight
      } else {
        direction = .leftToRight
      }
    }
    directionsByParagraphStart[paragraphRange.location] = direction
    return direction
  }
  func enumerateCaretOffsetsInLineFragment(
    at location: any NSTextLocation,
    using block: (CGFloat, any NSTextLocation, Bool, UnsafeMutablePointer<ObjCBool>) -> Void
  ) {
    guard let position = location as? ProbeLocation,
      let navigationLayout,
      let fragment = layoutFragment(at: location, in: navigationLayout),
      let elementStart = fragment.textElement?.elementRange?.location as? ProbeLocation,
      let line = fragment.textLineFragment(
        for: location, isUpstreamAffinity: position.offset == source.length)
    else { return }
    let lineStart = elementStart.offset + line.characterRange.location
    let lineEnd = lineStart + line.characterRange.length
    let string = source.string as NSString
    var boundaries = [lineStart]
    var cursor = lineStart
    while cursor < lineEnd {
      let cluster = string.rangeOfComposedCharacterSequence(at: cursor)
      guard cluster.length > 0 else { return }
      cursor = min(NSMaxRange(cluster), lineEnd)
      boundaries.append(cursor)
    }
    let caretValues = boundaries.map { boundary in
      (
        line.locationForCharacter(at: boundary - elementStart.offset).x,
        ProbeLocation(boundary)
      )
    }.sorted { $0.0 < $1.0 }
    for (offset, caretLocation) in caretValues {
      var stop = ObjCBool(false)
      withUnsafeMutablePointer(to: &stop) { block(offset, caretLocation, true, $0) }
      if stop.boolValue { break }
    }
    _ = position
  }
  func layoutFragment(
    at location: any NSTextLocation, in layout: NSTextLayoutManager
  ) -> NSTextLayoutFragment? {
    var result: NSTextLayoutFragment?
    _ = layout.enumerateTextLayoutFragments(from: location, options: [.ensuresLayout]) {
      fragment in
      result = fragment
      return false
    }
    return result
  }
  func lineFragmentRange(for point: CGPoint, inContainerAt location: any NSTextLocation)
    -> NSTextRange?
  {
    guard let navigationLayout,
      let fragment = navigationLayout.textLayoutFragment(for: point),
      let elementRange = fragment.textElement?.elementRange,
      let elementStart = elementRange.location as? ProbeLocation
    else { return nil }
    let localPoint = CGPoint(
      x: point.x - fragment.layoutFragmentFrame.minX,
      y: point.y - fragment.layoutFragmentFrame.minY)
    guard
      let line = fragment.textLineFragments.first(where: {
        $0.typographicBounds.contains(localPoint)
      })
    else { return nil }
    let start = elementStart.offset + line.characterRange.location
    let end = start + line.characterRange.length
    return NSTextRange(location: ProbeLocation(start), end: ProbeLocation(end))
  }
}

@MainActor func run(
  _ name: String, _ text: String, preparedPlan: ChunkPlan? = nil, targetOffsets: [Int]? = nil
) throws {
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let source = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
  let original: [(Int, Int, UInt)]
  var chunks: [(Int, Int)]
  if let preparedPlan {
    original = preparedPlan.lines
    chunks = preparedPlan.ranges
  } else {
    original = try Planner().lines(source)
    chunks = []
    var start = 0
    for line in original {
      let end = line.0 + line.1
      if end - start >= 4096 {
        chunks.append((start, end))
        start = end
      }
    }
    if start < source.length { chunks.append((start, source.length)) }
  }
  let lineRanges = original.map { ($0.0, $0.0 + $0.1) }
  let manager = ChunkManager(source: source, ranges: chunks, lineRanges: lineRanges)
  let layout = NSTextLayoutManager()
  manager.addTextLayoutManager(layout)
  manager.primaryTextLayoutManager = layout
  layout.textContainer = NSTextContainer(
    size: NSSize(width: 858, height: CGFloat.greatestFiniteMagnitude))
  manager.navigationLayout = layout
  let range = manager.documentRange
  if preparedPlan == nil { layout.ensureLayout(for: range) }
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
  let chunkBoundaries = chunks.dropFirst().map(\.0)
  let boundariesToCheck =
    preparedPlan == nil
    ? chunkBoundaries
    : Array(chunkBoundaries.filter { abs($0 - source.length / 2) < 8192 }.prefix(1))
  for boundary in boundariesToCheck {
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
  let offsets = targetOffsets ?? [min(5_000, source.length - 1)]
  for lineOffset in offsets {
    guard let selectedLine = manager.textRange(for: .line, enclosing: ProbeLocation(lineOffset)),
      let expectedLine = lineRanges.first(where: { $0.0 <= lineOffset && lineOffset < $0.1 }),
      (selectedLine.location as? ProbeLocation)?.offset == expectedLine.0,
      (selectedLine.endLocation as? ProbeLocation)?.offset == expectedLine.1
    else { throw NSError(domain: "navigation", code: 9) }
    let lineSelection = navigation.textSelection(
      for: .line, enclosing: NSTextSelection(ProbeLocation(lineOffset), affinity: .downstream))
    guard
      let selectedRange = lineSelection.textRanges.first,
      (selectedRange.location as? ProbeLocation)?.offset == expectedLine.0,
      (selectedRange.endLocation as? ProbeLocation)?.offset == expectedLine.1
    else { throw NSError(domain: "navigation", code: 10) }
    var caretLocations: [Int] = []
    var caretOffsets: [CGFloat] = []
    manager.enumerateCaretOffsetsInLineFragment(at: ProbeLocation(lineOffset)) {
      offset, caret, _, _ in
      guard let caret = caret as? ProbeLocation else { return }
      caretLocations.append(caret.offset)
      caretOffsets.append(offset)
    }
    guard caretLocations.min() == expectedLine.0, caretLocations.max() == expectedLine.1,
      zip(caretOffsets, caretOffsets.dropFirst()).allSatisfy({ $0 <= $1 })
    else { throw NSError(domain: "navigation", code: 11) }
    guard let fragment = manager.layoutFragment(at: ProbeLocation(lineOffset), in: layout),
      let line = fragment.textLineFragment(
        for: ProbeLocation(lineOffset), isUpstreamAffinity: false)
    else { throw NSError(domain: "navigation", code: 12) }
    let pointInLine = CGPoint(
      x: fragment.layoutFragmentFrame.minX + line.typographicBounds.midX,
      y: fragment.layoutFragmentFrame.minY + line.typographicBounds.midY)
    guard
      let hitLine = manager.lineFragmentRange(
        for: pointInLine, inContainerAt: ProbeLocation(lineOffset)),
      (hitLine.location as? ProbeLocation)?.offset == expectedLine.0,
      (hitLine.endLocation as? ProbeLocation)?.offset == expectedLine.1
    else { throw NSError(domain: "navigation", code: 13) }
    if let lineIndex = lineRanges.firstIndex(where: { $0.0 <= lineOffset && lineOffset < $0.1 }),
      lineIndex + 1 < lineRanges.count
    {
      let nextLine = lineRanges[lineIndex + 1]
      guard
        let down = navigation.destinationSelection(
          for: NSTextSelection(ProbeLocation(expectedLine.0), affinity: .downstream),
          direction: .down, destination: .character, extending: false, confined: false
        )?.textRanges.first?.location as? ProbeLocation,
        nextLine.0 <= down.offset, down.offset < nextLine.1
      else { throw NSError(domain: "navigation", code: 14) }
    }
  }
  print(
    "navigation case=\(name) documentEnd=\(documentEnd.offset) firstGraphemeEnd=\(nextCharacter.offset) lastGraphemeStart=\(lastBackward.offset) paragraphSelection=passed visualLineSelection=passed caretEnumeration=passed pointToLine=passed verticalMovement=passed"
  )
  if let preparedPlan {
    var exact = true
    for offset in offsets {
      guard let chunk = chunks.first(where: { $0.0 <= offset && offset < $0.1 }),
        let fragment = manager.layoutFragment(at: ProbeLocation(offset), in: layout),
        let elementStart = fragment.textElement?.elementRange?.location as? ProbeLocation
      else {
        exact = false
        continue
      }
      let actual = fragment.textLineFragments.map {
        (
          elementStart.offset + $0.characterRange.location, $0.characterRange.length,
          $0.typographicBounds.width.bitPattern
        )
      }
      let expected = preparedPlan.lines.filter { $0.0 >= chunk.0 && $0.0 + $0.1 <= chunk.1 }
      exact =
        exact && expected.count == actual.count
        && zip(expected, actual).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
    }
    guard exact else { throw NSError(domain: "navigation", code: 15) }
    print(
      "managerAttached=\(layout.textContentManager === manager) emitted=\(manager.emitted) case=\(name) utf16=\(source.length) chunks=\(chunks.count) targetedGeometryExact=\(exact)"
    )
  } else {
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
    guard exact else { throw NSError(domain: "navigation", code: 16) }
    let diff = zip(original, actual).enumerated().first { $0.element.0 != $0.element.1 }
    print(
      "managerAttached=\(layout.textContentManager === manager) fragments=\(fragmentsSeen) emitted=\(manager.emitted) case=\(name) utf16=\(source.length) chunks=\(chunks.count) nativeLines=\(original.count) customManagerLines=\(actual.count) exact=\(exact) firstDiff=\(String(describing: diff))"
    )
  }
}

@main @MainActor enum Main {
  static func main() async throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    if CommandLine.arguments.contains("--ten-mib") {
      let header = "123456789012345\n"
      let text = header + String(repeating: "خط📝", count: (10_485_760 - header.utf8.count) / 8)
      let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
      let style = NSMutableParagraphStyle()
      style.baseWritingDirection = .natural
      let source = NSAttributedString(
        string: text, attributes: [.font: font, .paragraphStyle: style])
      let planningStart = ProcessInfo.processInfo.systemUptime
      let plan = try await planChunks(source)
      let planningSeconds = ProcessInfo.processInfo.systemUptime - planningStart
      fputs(
        "planner seconds=\(planningSeconds) chunks=\(plan.ranges.count) lines=\(plan.lines.count)\n",
        stderr)
      try run(
        "ten-mib", text, preparedPlan: plan,
        targetOffsets: [source.length / 2, source.length - 1_024])
    } else {
      try run("rtl-emoji", String(repeating: "خط📝", count: 2000))
      try run("mixed", String(repeating: "abc اردو 123 — שלום🙂 ", count: 500))
      try run("combining", String(repeating: "e\u{301} العربية العربية אבג 🧑🏽‍💻 ", count: 500))
      try run("punctuation", String(repeating: "(rtl: العربية 42) [עברית, 7] — 🙂 ", count: 500))
    }
  }
}
