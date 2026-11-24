import AppKit
import CryptoKit
import Foundation

@main
@MainActor
enum TextKit2WrapControlProbe {
  static func main() {
    guard CommandLine.arguments.count == 3,
      let byteCount = Int(CommandLine.arguments[1]),
      [16_384, 1_048_576, 10_485_760].contains(byteCount),
      ["wrap", "no-wrap"].contains(CommandLine.arguments[2])
    else { exit(EX_CONFIG) }

    do {
      let result = try run(byteCount: byteCount, wraps: CommandLine.arguments[2] == "wrap")
      let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
      print(String(decoding: data, as: UTF8.self))
    } catch {
      FileHandle.standardError.write(Data("probe failed: \(error)\n".utf8))
      exit(1)
    }
  }

  private static func run(byteCount: Int, wraps: Bool) throws -> [String: Any] {
    let header = "123456789012345\n"
    let unit = "خط📝"
    let text = header + String(repeating: unit, count: (byteCount - 16) / 8)
    guard text.utf8.count == byteCount else { throw Failure.fixtureSize }

    let frame = NSRect(x: 0, y: 0, width: 900, height: 500)
    let editor = NSTextView(usingTextLayoutManager: true)
    editor.frame = frame
    editor.isRichText = false
    editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
    editor.textContainerInset = NSSize(width: 16, height: 16)
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = !wraps
    editor.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    guard let storage = editor.textStorage, let container = editor.textContainer,
      let layout = editor.textLayoutManager, let content = layout.textContentManager
    else { throw Failure.textSystemUnavailable }

    let scroll = NSScrollView(frame: frame)
    scroll.hasHorizontalScroller = !wraps
    editor.autoresizingMask = wraps ? [.width] : []
    container.widthTracksTextView = wraps
    if !wraps { editor.setFrameSize(NSSize(width: 900, height: frame.height)) }
    container.containerSize = NSSize(
      width: wraps ? CGFloat(868) : CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude)
    scroll.documentView = editor
    editor.string = text

    let started = ContinuousClock.now
    layout.ensureLayout(for: content.documentRange)
    let elapsed = started.duration(to: .now)
    var lineCount = 0
    var coveredUTF16 = 0
    var contiguousCoverage = true
    var geometry: [String] = []
    _ = layout.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
      guard let elementRange = fragment.textElement?.elementRange else {
        contiguousCoverage = false
        return true
      }
      let elementStart = content.offset(
        from: content.documentRange.location, to: elementRange.location)
      for line in fragment.textLineFragments {
        lineCount += 1
        let lineStart = elementStart + line.characterRange.location
        if lineStart != coveredUTF16 { contiguousCoverage = false }
        coveredUTF16 = lineStart + line.characterRange.length
        geometry.append(
          "\(lineStart):\(line.characterRange.length):\(line.typographicBounds.width.bitPattern):\(line.typographicBounds.height.bitPattern)"
        )
      }
      return true
    }
    let geometryHash = SHA256.hash(data: Data(geometry.joined(separator: ";").utf8))
      .map { String(format: "%02x", $0) }.joined()
    let parts = elapsed.components
    let elapsedNanoseconds =
      UInt64(parts.seconds) * 1_000_000_000
      + UInt64(parts.attoseconds / 1_000_000_000)
    return [
      "requestedUTF8Bytes": byteCount,
      "actualUTF8Bytes": storage.string.utf8.count,
      "textSHA256": SHA256.hash(data: Data(storage.string.utf8)).map {
        String(format: "%02x", $0)
      }.joined(),
      "sourceUTF16": storage.length,
      "wrapMode": wraps ? "wrap" : "no-wrap",
      "elapsedNanoseconds": elapsedNanoseconds,
      "lineCount": lineCount,
      "coveredUTF16": coveredUTF16,
      "completeCoverage": contiguousCoverage && coveredUTF16 == storage.length,
      "exactText": storage.string == text,
      "geometrySHA256": geometryHash,
    ]
  }

  private enum Failure: Error {
    case fixtureSize
    case textSystemUnavailable
  }
}
