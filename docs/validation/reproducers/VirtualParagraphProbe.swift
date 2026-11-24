import AppKit
import CryptoKit
import Foundation

final class ProbeLocation: NSObject, NSTextLocation {
  let offset: Int
  init(_ offset: Int) { self.offset = offset }
  func compare(_ location: any NSTextLocation) -> ComparisonResult {
    guard let other = location as? ProbeLocation else { return .orderedSame }
    if offset < other.offset { return .orderedAscending }
    if offset > other.offset { return .orderedDescending }
    return .orderedSame
  }
}

final class VirtualParagraphManager: NSTextContentManager {
  let source: NSAttributedString
  let chunkUnits: Int
  private(set) var emitted: [NSTextParagraph] = []

  init(source: NSAttributedString, chunkUnits: Int) {
    self.source = source
    self.chunkUnits = chunkUnits
    super.init()
  }
  required init?(coder: NSCoder) { return nil }

  override var documentRange: NSTextRange {
    NSTextRange(location: ProbeLocation(0), end: ProbeLocation(source.length))!
  }

  override func enumerateTextElements(
    from textLocation: (any NSTextLocation)?,
    options: NSTextContentManager.EnumerationOptions,
    using block: (NSTextElement) -> Bool
  ) -> (any NSTextLocation)? {
    guard options.contains(.reverse) == false else { return nil }
    let requested = (textLocation as? ProbeLocation)?.offset ?? 0
    let boundaries: [(Int, Int)]
    if chunkUnits > source.length {
      boundaries = [(0, source.length)]
    } else {
      var ranges: [(Int, Int)] = [(0, 16)]
      var start = 16
      while start < source.length {
        let end = min(source.length, start + chunkUnits)
        ranges.append((start, end))
        start = end
      }
      boundaries = ranges
    }
    for (start, end) in boundaries where end > requested {
      let start = max(start, requested / chunkUnits * chunkUnits)
      guard start < end else { continue }
      let attributed = source.attributedSubstring(from: NSRange(location: start, length: end - start))
      let para = NSTextParagraph(attributedString: attributed)
      para.textContentManager = self
      para.elementRange = NSTextRange(location: ProbeLocation(start), end: ProbeLocation(end))!
      emitted.append(para)
      if !block(para) { return ProbeLocation(end) }
    }
    return ProbeLocation(source.length)
  }

  override func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (any NSTextLocation)? {
    guard let location = location as? ProbeLocation else { return nil }
    let next = location.offset + offset
    guard (0...source.length).contains(next) else { return nil }
    return ProbeLocation(next)
  }

  override func offset(from: any NSTextLocation, to: any NSTextLocation) -> Int {
    guard let from = from as? ProbeLocation, let to = to as? ProbeLocation else { return NSNotFound }
    return to.offset - from.offset
  }
}

func geometry(totalBytes: Int, chunk: Int) throws -> [String: Any] {
  let unit = "خط📝"
  let header = "123456789012345\n"
  let repetitions = (totalBytes - header.utf8.count) / unit.utf8.count
  let text = header + String(repeating: unit, count: repetitions)
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
    .paragraphStyle: style,
  ]
  let source = NSAttributedString(string: text, attributes: attrs)
  let manager = VirtualParagraphManager(source: source, chunkUnits: chunk)
  let layout = NSTextLayoutManager()
  manager.addTextLayoutManager(layout)
  manager.primaryTextLayoutManager = layout
  let container = NSTextContainer(size: NSSize(width: 900, height: CGFloat.greatestFiniteMagnitude))
  layout.textContainer = container
  layout.ensureLayout(for: manager.documentRange)
  var lines = 0
  var lineUnits = 0
  var invalid = false
  var geometry = ""
  var geometryRows: [String] = []
  _ = layout.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout], using: { fragment in
    let elementStart = (fragment.textElement?.elementRange?.location as? ProbeLocation)?.offset ?? -1
    for line in fragment.textLineFragments {
      lines += 1
      lineUnits += line.characterRange.length
      if line.characterRange.location < 0 || NSMaxRange(line.characterRange) > source.length { invalid = true }
      let row = "\(elementStart + line.characterRange.location):\(line.characterRange.length):\(line.typographicBounds.width.bitPattern)"
      geometry += row + ";"
      if geometryRows.count < 5 { geometryRows.append(row) }
    }
    return true
  })
  return ["requestedFileUTF8Bytes": totalBytes, "actualFileUTF8Bytes": text.utf8.count, "chunkUnits": chunk, "sourceUTF16": source.length, "lines": lines, "lineUnits": lineUnits, "elements": manager.emitted.count, "invalid": invalid, "geometrySHA256": SHA256.hash(data: Data(geometry.utf8)).map { String(format: "%02x", $0) }.joined(), "geometryRows": geometryRows, "complete": lineUnits == source.length && !invalid]
}

let arguments = Array(CommandLine.arguments.dropFirst())
let totalBytes = Int(arguments.first ?? "16384") ?? 16384
let chunk = Int(arguments.dropFirst().first ?? "0") ?? 0
let result = try geometry(totalBytes: totalBytes, chunk: chunk == 0 ? Int.max / 2 : chunk)
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
