import AppKit
import CoreText
import CryptoKit
import Foundation

func run(bytes: Int, chunkUnits: Int, width: Double) throws {
  let header = "123456789012345\n"
  let unit = "خط📝"
  let text = header + String(repeating: unit, count: (bytes - header.utf8.count) / unit.utf8.count)
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
    .paragraphStyle: style,
  ]
  guard text.utf8.count == bytes else { throw NSError(domain: "probe", code: 3) }
  let source = NSAttributedString(string: text, attributes: attributes)
  var rows: [String] = []
  var covered = 0
  var lineCount = 0
  let started = ContinuousClock.now
  var rangeStart = 0
  let paragraphBreak = (header as NSString).length
  while rangeStart < source.length {
    let rangeEnd = rangeStart == 0 ? paragraphBreak : min(source.length, rangeStart + chunkUnits)
    let range = NSRange(location: rangeStart, length: rangeEnd - rangeStart)
    let attributed = source.attributedSubstring(from: range)
    let typesetter = CTTypesetterCreateWithAttributedString(attributed as CFAttributedString)
    var lineStart = 0
    while lineStart < attributed.length {
      let count = CTTypesetterSuggestLineBreak(typesetter, lineStart, width)
      guard count > 0 else { throw NSError(domain: "probe", code: 1) }
      let line = CTTypesetterCreateLine(
        typesetter, CFRange(location: lineStart, length: count))
      let width = CTLineGetTypographicBounds(line, nil, nil, nil)
      rows.append("\(rangeStart + lineStart):\(count):\(width.bitPattern)")
      lineCount += 1
      lineStart += count
      covered += count
    }
    rangeStart = rangeEnd
  }
  let elapsed = started.duration(to: .now)
  let digest = SHA256.hash(data: Data(rows.joined(separator: ";").utf8)).map {
    String(format: "%02x", $0)
  }.joined()
  let parts = elapsed.components
  let nanos = UInt64(parts.seconds) * 1_000_000_000 + UInt64(parts.attoseconds / 1_000_000_000)
  print(
    "bytes=\(source.string.utf8.count) utf16=\(source.length) chunk=\(chunkUnits) lines=\(lineCount) coverage=\(covered) elapsed_ns=\(nanos) geometry=\(digest)"
  )
  guard covered == source.length else { throw NSError(domain: "probe", code: 4) }
  if bytes <= 16_384 { print("ROWS=" + rows.joined(separator: ";")) }
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 3, let bytes = Int(args[0]), let chunkUnits = Int(args[1]),
  let width = Double(args[2]), bytes >= 16, chunkUnits > 0
else {
  throw NSError(domain: "probe", code: 2)
}
try run(bytes: bytes, chunkUnits: chunkUnits, width: width)
