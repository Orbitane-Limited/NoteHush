import AppKit
import Foundation

@MainActor final class BoundedNativeShaper {
  private let storage = NSTextContentStorage()
  private let backing = NSTextStorage()
  private let manager = NSTextLayoutManager()
  init(width: CGFloat) {
    storage.textStorage = backing
    storage.addTextLayoutManager(manager)
    storage.primaryTextLayoutManager = manager
    manager.textContainer = NSTextContainer(
      size: NSSize(width: width, height: .greatestFiniteMagnitude))
  }
  func lines(_ attributed: NSAttributedString) throws -> [(Int, Int, UInt)] {
    backing.setAttributedString(attributed)
    guard
      let range = NSTextRange(
        location: storage.documentRange.location, end: storage.documentRange.endLocation)
    else { throw NSError(domain: "probe", code: 1) }
    manager.ensureLayout(for: range)
    var result: [(Int, Int, UInt)] = []
    _ = manager.enumerateTextLayoutFragments(from: range.location, options: []) { fragment in
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

@MainActor func planned(_ source: NSAttributedString, shaper: BoundedNativeShaper, cap: Int)
  async throws -> ([(Int, Int)], [(Int, Int, UInt)], [Double])
{
  var ranges: [(Int, Int)] = []
  var output: [(Int, Int, UInt)] = []
  var durations: [Double] = []
  var start = 0
  while start < source.length {
    let available = min(cap, source.length - start)
    let candidate = source.attributedSubstring(from: NSRange(location: start, length: available))
    let operationStart = ProcessInfo.processInfo.systemUptime
    let candidateLines = try shaper.lines(candidate)
    durations.append(ProcessInfo.processInfo.systemUptime - operationStart)
    var end = start + available
    if end < source.length, candidateLines.count > 1 {
      end =
        start + candidateLines[candidateLines.count - 2].0
        + candidateLines[candidateLines.count - 2].1
    }
    guard end > start else { throw NSError(domain: "probe", code: 2) }
    let completeLines = end == start + available ? candidateLines : Array(candidateLines.dropLast())
    ranges.append((start, end))
    output += completeLines.map { (start + $0.0, $0.1, $0.2) }
    start = end
    if ranges.count.isMultiple(of: 50) {
      fputs("progress chunks=\(ranges.count) covered=\(start)\n", stderr)
    }
    await Task.yield()
  }
  return (ranges, output, durations)
}

@MainActor func runCase(_ name: String, text: String, cap: Int = 4096, heartbeat: () -> Int)
  async throws
{
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let paragraph = NSMutableParagraphStyle()
  paragraph.baseWritingDirection = .natural
  let source = NSAttributedString(
    string: text, attributes: [.font: font, .paragraphStyle: paragraph])
  let shaper = BoundedNativeShaper(width: 858)
  let began = ProcessInfo.processInfo.systemUptime
  let (ranges, chunked, durations) = try await planned(source, shaper: shaper, cap: cap)
  let elapsed = ProcessInfo.processInfo.systemUptime - began
  if source.length <= 20_000 {
    let fullShaper = BoundedNativeShaper(width: 858)
    let native = try fullShaper.lines(source)
    let exact = native.elementsEqual(chunked) { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
    let firstDiff = zip(native, chunked).enumerated().first {
      $0.element.0.0 != $0.element.1.0 || $0.element.0.1 != $0.element.1.1
        || $0.element.0.2 != $0.element.1.2
    }
    print(
      "case=\(name) utf16=\(source.length) chunks=\(ranges.count) nativeLines=\(native.count) chunkLines=\(chunked.count) exact=\(exact) firstDiff=\(String(describing:firstDiff)) seconds=\(elapsed)"
    )
  } else {
    let sorted = durations.sorted()
    let p95 = sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count - 1) * 0.95)]
    print(
      "case=\(name) utf16=\(source.length) chunks=\(ranges.count) lines=\(chunked.count) coverage=\(chunked.reduce(0){$0+$1.1}) seconds=\(elapsed) maxWindowMs=\((sorted.last ?? 0) * 1000) p95WindowMs=\(p95 * 1000) heartbeat=\(heartbeat())"
    )
  }
}

@main @MainActor enum Main {
  static func main() async throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let cases: [(String, String)] = [
      ("rtl-emoji", String(repeating: "خط📝", count: 2000)),
      ("mixed-latin-numbers", String(repeating: "abc اردو 123 — שלום🙂 ", count: 500)),
      ("combining-rtl", String(repeating: "e\u{301} العربية العربية אבג 🧑🏽‍💻 ", count: 500)),
      ("punctuation-parens", String(repeating: "(rtl: العربية 42) [עברית, 7] — 🙂 ", count: 500)),
    ]
    for (name, text) in cases {
      try await runCase(name, text: text, cap: 4096, heartbeat: { 0 })
    }
    let large = "123456789012345\n" + String(repeating: "خط📝", count: (10_485_760 - 16) / 8)
    var ticks = 0
    let pulse = Task { @MainActor in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(16))
        ticks += 1
      }
    }
    try await runCase("ten-mib", text: large, cap: 4096, heartbeat: { ticks })
    pulse.cancel()
  }
}
