import AppKit
import CryptoKit
import Foundation

final class ChunkedContentStorage: NSTextContentStorage {
  let chunkUnits: Int

  init(chunkUnits: Int) {
    self.chunkUnits = chunkUnits
    super.init()
  }

  required init?(coder: NSCoder) { return nil }

  override func enumerateTextElements(
    from textLocation: (any NSTextLocation)?,
    options: NSTextContentManager.EnumerationOptions,
    using block: (NSTextElement) -> Bool
  ) -> (any NSTextLocation)? {
    guard let storage = textStorage else { return nil }
    let documentStart = documentRange.location
    let total = storage.length
    let requested =
      textLocation.map { offset(from: documentStart, to: $0) }
      ?? (options.contains(.reverse) ? total : 0)
    guard requested >= 0, requested <= total else { return nil }

    func location(_ offset: Int) -> (any NSTextLocation)? {
      super.location(documentStart, offsetBy: offset)
    }

    if options.contains(.reverse) {
      var end = min(total, requested)
      while end > 0 {
        let start = max(0, end - chunkUnits)
        guard let startLocation = location(start), let endLocation = location(end),
          let range = NSTextRange(location: startLocation, end: endLocation)
        else { return nil }
        let attributed = storage.attributedSubstring(
          from: NSRange(location: start, length: end - start))
        let paragraph = NSTextParagraph(attributedString: attributed)
        paragraph.textContentManager = self
        paragraph.elementRange = range
        if !block(paragraph) { return startLocation }
        end = start
      }
      return location(0)
    }

    var start = (requested / chunkUnits) * chunkUnits
    var lastEnd = start
    while start < total {
      let end = min(total, start + chunkUnits)
      guard let startLocation = location(start), let endLocation = location(end),
        let range = NSTextRange(location: startLocation, end: endLocation)
      else { return nil }
      let attributed = storage.attributedSubstring(
        from: NSRange(location: start, length: end - start))
      let paragraph = NSTextParagraph(attributedString: attributed)
      paragraph.textContentManager = self
      paragraph.elementRange = range
      if !block(paragraph) { return endLocation }
      lastEnd = end
      start = end
    }
    return location(lastEnd)
  }
}

@main
@MainActor
enum NSTextViewReplaceManagerProbe {
  static func main() {
    guard CommandLine.arguments.count == 3,
      let byteCount = Int(CommandLine.arguments[1]),
      [16_384, 10_485_760].contains(byteCount),
      ["full", "viewport"].contains(CommandLine.arguments[2])
    else { exit(EX_CONFIG) }

    do {
      let result = try run(byteCount: byteCount, targetMode: CommandLine.arguments[2])
      print(
        String(
          decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
          as: UTF8.self))
    } catch {
      FileHandle.standardError.write(Data("probe failed: \(error)\n".utf8))
      exit(1)
    }
  }

  private static func run(byteCount: Int, targetMode: String) throws -> [String: Any] {
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
    editor.isHorizontallyResizable = false
    editor.autoresizingMask = [.width]
    guard let storage = editor.textStorage, let layout = editor.textLayoutManager,
      let container = editor.textContainer
    else { throw Failure.textSystemUnavailable }
    container.widthTracksTextView = true
    container.containerSize = NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude)
    editor.string = text
    guard let initialContent = layout.textContentManager else {
      throw Failure.textSystemUnavailable
    }

    let replacement = ChunkedContentStorage(chunkUnits: 4_032)
    replacement.textStorage = storage
    layout.replace(replacement)
    let replacementAttached = layout.textContentManager === replacement
    let textViewContentAttached = editor.textContentStorage === replacement

    let start = targetMode == "full" ? 0 : (storage.length / 2 / 4_032) * 4_032
    let length = targetMode == "full" ? storage.length : min(1_024, storage.length - start)
    guard
      let startLocation = replacement.location(replacement.documentRange.location, offsetBy: start),
      let endLocation = replacement.location(
        replacement.documentRange.location, offsetBy: start + length),
      let target = NSTextRange(location: startLocation, end: endLocation)
    else { throw Failure.locationUnavailable }

    let started = ContinuousClock.now
    layout.ensureLayout(for: target)
    let layoutNanoseconds = nanoseconds(started.duration(to: .now))
    var lineCount = 0
    var covered = start
    var contiguous = true
    var geometry: [String] = []
    _ = layout.enumerateTextLayoutFragments(from: startLocation, options: [.ensuresLayout]) {
      fragment in
      guard let elementRange = fragment.textElement?.elementRange else {
        contiguous = false
        return false
      }
      let elementStart = replacement.offset(
        from: replacement.documentRange.location, to: elementRange.location)
      for line in fragment.textLineFragments {
        let lineStart = elementStart + line.characterRange.location
        if lineStart != covered { contiguous = false }
        covered = lineStart + line.characterRange.length
        lineCount += 1
        geometry.append(
          "\(lineStart):\(line.characterRange.length):\(line.typographicBounds.width.bitPattern)")
      }
      return targetMode == "full" ? true : covered < start + length
    }

    let original = editor.string
    let selection = editor.selectedRange()
    editor.insertText("X", replacementRange: NSRange(location: 0, length: 0))
    let editPreserved =
      editor.string.utf16.count == original.utf16.count + 1
      && editor.string.utf16.first == 88
      && editor.string.utf16.dropFirst().elementsEqual(original.utf16)
    let undo = editor.undoManager
    if undo?.canUndo == true { undo?.undo() }
    let undoPreserved = editor.string == original

    return [
      "requestedUTF8Bytes": byteCount,
      "actualUTF8Bytes": storage.string.utf8.count,
      "textSHA256": SHA256.hash(data: Data(storage.string.utf8)).map { String(format: "%02x", $0) }
        .joined(),
      "sourceUTF16": storage.length,
      "targetMode": targetMode,
      "targetUTF16": [start, length],
      "layoutNanoseconds": layoutNanoseconds,
      "lineCount": lineCount,
      "coveredThroughUTF16": covered,
      "contiguousTargetCoverage": contiguous && covered >= start + length,
      "exactText": original == text,
      "geometrySHA256": SHA256.hash(data: Data(geometry.joined(separator: ";").utf8)).map {
        String(format: "%02x", $0)
      }.joined(),
      "replacementManagerAttachedToLayout": replacementAttached,
      "textViewContentStorageIsReplacement": textViewContentAttached,
      "initialManagerWasTextContentStorage": initialContent is NSTextContentStorage,
      "textStorageIdentityPreserved": editor.textStorage === storage,
      "editPreserved": editPreserved,
      "undoPreserved": undoPreserved,
      "selectionBeforeEdit": [selection.location, selection.length],
      "selectionAfterUndo": [editor.selectedRange().location, editor.selectedRange().length],
    ]
  }

  private static func nanoseconds(_ duration: Duration) -> UInt64 {
    let parts = duration.components
    return UInt64(parts.seconds) * 1_000_000_000 + UInt64(parts.attoseconds / 1_000_000_000)
  }

  private enum Failure: Error {
    case fixtureSize
    case textSystemUnavailable
    case locationUnavailable
  }
}
