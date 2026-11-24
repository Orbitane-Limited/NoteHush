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

@MainActor final class Shaper {
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
    var rows: [(Int, Int, UInt)] = []
    _ = layout.enumerateTextLayoutFragments(from: range.location, options: [.ensuresLayout]) {
      fragment in
      guard let elementRange = fragment.textElement?.elementRange else { return false }
      let base = storage.offset(from: storage.documentRange.location, to: elementRange.location)
      for line in fragment.textLineFragments {
        rows.append(
          (
            base + line.characterRange.location, line.characterRange.length,
            line.typographicBounds.width.bitPattern
          ))
      }
      return true
    }
    return rows
  }
}

final class ChunkManager: NSTextContentManager {
  let source: NSAttributedString
  let ranges: [(Int, Int)]
  private(set) var emitted = 0
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
    guard let start = from as? ProbeLocation, let end = to as? ProbeLocation else {
      return NSNotFound
    }
    return end.offset - start.offset
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
      let value = source.attributedSubstring(from: NSRange(location: start, length: end - start))
      let paragraph = NSTextParagraph(attributedString: value)
      paragraph.textContentManager = self
      paragraph.elementRange = NSTextRange(location: ProbeLocation(start), end: ProbeLocation(end))!
      emitted += 1
      last = ProbeLocation(reverse ? start : end)
      if !block(paragraph) { return last }
    }
    return last
  }
}

@MainActor func plan(_ source: NSAttributedString, cap: Int) async throws -> (
  [(Int, Int)], [(Int, Int, UInt)]
) {
  let shaper = Shaper()
  var ranges: [(Int, Int)] = []
  var lines: [(Int, Int, UInt)] = []
  var start = 0
  while start < source.length {
    let available = min(cap, source.length - start)
    let candidate = source.attributedSubstring(from: NSRange(location: start, length: available))
    let rows = try shaper.lines(candidate)
    var end = start + available
    if end < source.length && rows.count > 1 {
      end = start + rows[rows.count - 2].0 + rows[rows.count - 2].1
    }
    let complete = end == start + available ? rows : Array(rows.dropLast())
    guard end > start else { throw NSError(domain: "probe", code: 1) }
    ranges.append((start, end))
    lines.append(contentsOf: complete.map { (start + $0.0, $0.1, $0.2) })
    start = end
    if ranges.count.isMultiple(of: 100) {
      fputs("planned chunks=\(ranges.count) covered=\(start)\n", stderr)
    }
    await Task.yield()
  }
  return (ranges, lines)
}

@MainActor func run() async throws {
  let bytes = 10_485_760
  let header = "123456789012345\n"
  let text = header + String(repeating: "خط📝", count: (bytes - header.utf8.count) / 8)
  guard text.utf8.count == bytes else { throw NSError(domain: "probe", code: 2) }
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let source = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
  let plannerStart = ProcessInfo.processInfo.systemUptime
  let (ranges, expected) = try await plan(source, cap: 4096)
  let plannerSeconds = ProcessInfo.processInfo.systemUptime - plannerStart
  fputs(
    "planned chunks=\(ranges.count) lines=\(expected.count) covered=\(ranges.last?.1 ?? 0) plannerSeconds=\(plannerSeconds)\n",
    stderr)
  let manager = ChunkManager(source: source, ranges: ranges)
  let layout = NSTextLayoutManager()
  manager.addTextLayoutManager(layout)
  manager.primaryTextLayoutManager = layout
  layout.textContainer = NSTextContainer(
    size: NSSize(width: 858, height: CGFloat.greatestFiniteMagnitude))
  let doc = manager.documentRange
  let targets = [0, source.length / 2, source.length - 1024]
  for target in targets {
    let start = max(0, target)
    let end = min(source.length, start + 1024)
    let a = manager.location(doc.location, offsetBy: start)!
    let b = manager.location(a, offsetBy: end - start)!
    let requested = NSTextRange(location: a, end: b)!
    fputs("begin targeted native chunked layout offset=\(start)\n", stderr)
    let layoutStart = ProcessInfo.processInfo.systemUptime
    layout.ensureLayout(for: requested)
    var actual: [(Int, Int, UInt)] = []
    _ = layout.enumerateTextLayoutFragments(from: a, options: [.ensuresLayout]) { fragment in
      guard let elementRange = fragment.textElement?.elementRange else { return false }
      let base = manager.offset(from: doc.location, to: elementRange.location)
      for line in fragment.textLineFragments {
        actual.append(
          (
            base + line.characterRange.location, line.characterRange.length,
            line.typographicBounds.width.bitPattern
          ))
      }
      return actual.last.map { $0.0 + $0.1 < end } ?? true
    }
    let layoutSeconds = ProcessInfo.processInfo.systemUptime - layoutStart
    let expectedSlice = expected.filter { $0.0 < end && $0.0 + $0.1 > start }
    let actualSlice = actual.filter { $0.0 < end && $0.0 + $0.1 > start }
    let exact =
      expectedSlice.count == actualSlice.count
      && zip(expectedSlice, actualSlice).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
    print(
      "offset=\(start) chunks=\(ranges.count) emitted=\(manager.emitted) expectedLines=\(expectedSlice.count) actualLines=\(actualSlice.count) exactGeometry=\(exact) plannerSeconds=\(plannerSeconds) layoutSeconds=\(layoutSeconds)"
    )
  }
}

@main @MainActor enum Main {
  static func main() async throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    try await run()
  }
}
