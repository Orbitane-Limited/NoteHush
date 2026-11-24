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
  let elementLimit: Int
  private(set) var emitted: [NSTextParagraph] = []

  init(source: NSAttributedString, chunkUnits: Int, elementLimit: Int = Int.max) {
    self.source = source
    self.chunkUnits = chunkUnits
    self.elementLimit = elementLimit
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
    var emittedCount = 0
    var lastEnd = requested
    for (start, end) in boundaries where end > requested {
      let attributed = source.attributedSubstring(
        from: NSRange(location: start, length: end - start))
      let para = NSTextParagraph(attributedString: attributed)
      para.textContentManager = self
      para.elementRange = NSTextRange(location: ProbeLocation(start), end: ProbeLocation(end))!
      emitted.append(para)
      if !block(para) { return ProbeLocation(end) }
      emittedCount += 1
      lastEnd = end
      if emittedCount >= elementLimit { break }
    }
    return ProbeLocation(lastEnd)
  }

  override func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (
    any NSTextLocation
  )? {
    guard let location = location as? ProbeLocation else { return nil }
    let next = location.offset + offset
    guard (0...source.length).contains(next) else { return nil }
    return ProbeLocation(next)
  }

  override func offset(from: any NSTextLocation, to: any NSTextLocation) -> Int {
    guard let from = from as? ProbeLocation, let to = to as? ProbeLocation else {
      return NSNotFound
    }
    return to.offset - from.offset
  }
}

func geometry(totalBytes: Int, chunk: Int, mode: String, limitSuspicious: Bool) throws -> [String:
  Any]
{
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
  let manager = VirtualParagraphManager(
    source: source, chunkUnits: chunk, elementLimit: mode == "full" ? Int.max : 8)
  let layout = NSTextLayoutManager()
  layout.limitsLayoutForSuspiciousContents = limitSuspicious
  manager.addTextLayoutManager(layout)
  manager.primaryTextLayoutManager = layout
  let container = NSTextContainer(size: NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude))
  layout.textContainer = container
  let targetStart: Int
  switch mode {
  case "viewport-header": targetStart = 0
  case "viewport-start": targetStart = header.utf16.count
  case "viewport-middle": targetStart = source.length / 2
  case "viewport-end": targetStart = max(0, source.length - 128)
  default: targetStart = 0
  }
  let targetLength = min(
    mode == "viewport-header" ? header.utf16.count : 1_024, source.length - targetStart)
  let targetEnd = targetStart + targetLength
  let targetRange = NSTextRange(
    location: ProbeLocation(targetStart), end: ProbeLocation(targetEnd))!
  layout.ensureLayout(for: mode == "full" ? manager.documentRange : targetRange)
  var lines = 0
  var lineUnits = 0
  var invalid = false
  var geometry = ""
  var geometryRows: [String] = []
  var allGeometryRows: [(String, NSRange)] = []
  var lineRanges: [NSRange] = []
  var targetCoveredThrough = targetStart
  _ = layout.enumerateTextLayoutFragments(
    from: ProbeLocation(targetStart), options: [.ensuresLayout],
    using: { fragment in
      let elementStart =
        (fragment.textElement?.elementRange?.location as? ProbeLocation)?.offset ?? -1
      for line in fragment.textLineFragments {
        lines += 1
        lineUnits += line.characterRange.length
        let lineStart = elementStart + line.characterRange.location
        lineRanges.append(NSRange(location: lineStart, length: line.characterRange.length))
        if line.characterRange.location < 0 || NSMaxRange(line.characterRange) > source.length {
          invalid = true
        }
        let row =
          "\(lineStart):\(line.characterRange.length):\(line.typographicBounds.width.bitPattern)"
        geometry += row + ";"
        if geometryRows.count < 5 { geometryRows.append(row) }
        allGeometryRows.append(
          (row, NSRange(location: lineStart, length: line.characterRange.length)))
      }
      var cursor = targetStart
      for range in lineRanges.sorted(by: { $0.location < $1.location })
      where NSMaxRange(range) > cursor {
        if range.location > cursor { break }
        cursor = NSMaxRange(range)
      }
      targetCoveredThrough = cursor
      return mode == "full" || targetCoveredThrough < targetEnd
    })
  let targetCovered = targetCoveredThrough >= targetEnd
  let targetRows =
    allGeometryRows
    .filter { $0.1.location < targetEnd && NSMaxRange($0.1) > targetStart }
    .sorted { $0.1.location < $1.1.location }
    .map(\.0)
  let targetGeometry = targetRows.joined(separator: ";")
  return [
    "mode": mode, "limitsLayoutForSuspiciousContents": limitSuspicious,
    "targetStartUTF16": targetStart, "targetLengthUTF16": targetLength,
    "targetCoveredByLaidOutLines": targetCovered, "targetGeometryRows": targetRows,
    "targetGeometrySHA256": SHA256.hash(data: Data(targetGeometry.utf8)).map {
      String(format: "%02x", $0)
    }.joined(), "requestedFileUTF8Bytes": totalBytes, "actualFileUTF8Bytes": text.utf8.count,
    "chunkUnits": chunk, "sourceUTF16": source.length, "lines": lines, "lineUnits": lineUnits,
    "elements": manager.emitted.count, "invalid": invalid,
    "geometrySHA256": SHA256.hash(data: Data(geometry.utf8)).map { String(format: "%02x", $0) }
      .joined(), "geometryRows": geometryRows,
    "lineGeometry": allGeometryRows.map { $0.0 },
    "complete": mode == "full" && lineUnits == source.length && !invalid,
  ]
}

let arguments = Array(CommandLine.arguments.dropFirst())
let totalBytes = Int(arguments.first ?? "16384") ?? 16384
let chunk = Int(arguments.dropFirst().first ?? "0") ?? 0
let mode = arguments.dropFirst(2).first ?? "full"
let limitSuspicious = arguments.dropFirst(3).first == "true"
let result = try geometry(
  totalBytes: totalBytes, chunk: chunk == 0 ? Int.max / 2 : chunk, mode: mode,
  limitSuspicious: limitSuspicious)
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
