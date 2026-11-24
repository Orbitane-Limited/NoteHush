import AppKit
import Foundation

@MainActor final class Shaper {
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

@MainActor func plan(_ source: NSAttributedString, cap: Int) throws -> [(Int, Int, UInt)] {
  let shaper = Shaper()
  var output: [(Int, Int, UInt)] = []
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
    guard end > start else { throw NSError(domain: "probe", code: 2) }
    output += complete.map { (start + $0.0, $0.1, $0.2) }
    start = end
    if output.count.isMultiple(of: 10_000) {
      fputs("planned lines=\(output.count) covered=\(start)\n", stderr)
    }
  }
  return output
}

@MainActor func run() throws {
  let bytes = 10_485_760
  let header = "123456789012345\n"
  let sourceText = header + String(repeating: "خط📝", count: (bytes - header.utf8.count) / 8)
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let source = NSAttributedString(
    string: sourceText, attributes: [.font: font, .paragraphStyle: style])
  let began = ProcessInfo.processInfo.systemUptime
  let planStart = ProcessInfo.processInfo.systemUptime
  let planned = try plan(source, cap: 4096)
  let planSeconds = ProcessInfo.processInfo.systemUptime - planStart
  fputs(
    "planned rows=\(planned.count) sourceUTF16=\(source.length) seconds=\(planSeconds)\n", stderr)
  let src = sourceText as NSString
  let transformed = NSMutableString(capacity: source.length + planned.count)
  var sourceOffset = 0
  for (index, row) in planned.enumerated() {
    transformed.append(src.substring(with: NSRange(location: sourceOffset, length: row.1)))
    sourceOffset += row.1
    if index + 1 < planned.count { transformed.append("\u{2028}") }
  }
  guard sourceOffset == source.length else { throw NSError(domain: "probe", code: 3) }
  let presented = NSAttributedString(
    string: transformed as String, attributes: [.font: font, .paragraphStyle: style])
  let layoutStart = ProcessInfo.processInfo.systemUptime
  let shaped = try Shaper().lines(presented)
  let layoutSeconds = ProcessInfo.processInfo.systemUptime - layoutStart
  var mapped: [(Int, Int, UInt)] = []
  var logicalOffset = 0
  let presentedNSString = transformed as String as NSString
  for row in shaped {
    let physical = presentedNSString.substring(with: NSRange(location: row.0, length: row.1))
    let clean = physical.replacingOccurrences(of: "\u{2028}", with: "")
    let length = (clean as NSString).length
    if length > 0 {
      mapped.append((logicalOffset, length, row.2))
      logicalOffset += length
    }
  }
  let mismatch = zip(planned, mapped).enumerated().first {
    $0.element.0.0 != $0.element.1.0 || $0.element.0.1 != $0.element.1.1
      || $0.element.0.2 != $0.element.1.2
  }
  print(
    "sourceBytes=\(sourceText.utf8.count) sourceUTF16=\(source.length) plannedLines=\(planned.count) transformedUTF16=\(presented.length) shapedLines=\(shaped.count) mappedLines=\(mapped.count) logicalCoverage=\(logicalOffset) mismatch=\(String(describing: mismatch)) planSeconds=\(planSeconds) transformedLayoutSeconds=\(layoutSeconds) totalSeconds=\(ProcessInfo.processInfo.systemUptime - began)"
  )
}

@main @MainActor enum Main {
  static func main() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    try run()
  }
}
