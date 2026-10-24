import AppKit
import CryptoKit
import Foundation

final class ChunkedTextContentStorage: NSTextContentStorage {
  let chunkUnits: Int
  private(set) var emitted = 0

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
    guard let textStorage else { return nil }
    let range = documentRange
    let documentStart = range.location
    let documentEnd = range.endLocation
    let total = offset(from: documentStart, to: documentEnd)
    let requested =
      textLocation.map { offset(from: documentStart, to: $0) }
      ?? (options.contains(.reverse) ? total : 0)
    guard total >= 0, requested >= 0 else { return nil }

    func location(_ offset: Int) -> (any NSTextLocation)? {
      super.location(documentStart, offsetBy: offset)
    }

    if options.contains(.reverse) {
      var end = min(total, requested)
      while end > 0 {
        let start = max(0, end - chunkUnits)
        guard let startLocation = location(start), let endLocation = location(end),
          let elementRange = NSTextRange(location: startLocation, end: endLocation)
        else { return nil }
        let attributed = textStorage.attributedSubstring(
          from: NSRange(location: start, length: end - start))
        let paragraph = NSTextParagraph(attributedString: attributed)
        paragraph.textContentManager = self
        paragraph.elementRange = elementRange
        emitted += 1
        if !block(paragraph) { return startLocation }
        end = start
      }
      return location(0)
    }

    var start = requested
    if start == total { return location(total) }
    let newline = (textStorage.string as NSString).range(of: "\n")
    let firstParagraphEnd =
      newline.location == NSNotFound ? total : newline.location + newline.length
    if start >= firstParagraphEnd {
      start = firstParagraphEnd + ((start - firstParagraphEnd) / chunkUnits) * chunkUnits
    } else {
      start = 0
    }
    var lastEnd = start
    while start < total {
      let end = start == 0 ? min(total, firstParagraphEnd) : min(total, start + chunkUnits)
      guard let startLocation = location(start), let endLocation = location(end),
        let elementRange = NSTextRange(location: startLocation, end: endLocation)
      else { return nil }
      let attributed = textStorage.attributedSubstring(
        from: NSRange(location: start, length: end - start))
      let paragraph = NSTextParagraph(attributedString: attributed)
      paragraph.textContentManager = self
      paragraph.elementRange = elementRange
      emitted += 1
      if !block(paragraph) { return endLocation }
      lastEnd = end
      start = end
    }
    return location(lastEnd)
  }

  override func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (
    any NSTextLocation
  )? {
    super.location(location, offsetBy: offset)
  }

  override func offset(from: any NSTextLocation, to: any NSTextLocation) -> Int {
    super.offset(from: from, to: to)
  }
}

func run(bytes: Int, chunkUnits: Int, target: String) throws -> [String: Any] {
  let unit = "خط📝"
  let header = "123456789012345\n"
  let repetitions = (bytes - header.utf8.count) / unit.utf8.count
  let text = header + String(repeating: unit, count: repetitions)
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let source = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])

  let originalStorage = NSTextStorage(attributedString: source)
  let chunked = ChunkedTextContentStorage(chunkUnits: chunkUnits)
  chunked.textStorage = originalStorage
  let layout = NSTextLayoutManager()
  chunked.addTextLayoutManager(layout)
  chunked.primaryTextLayoutManager = layout
  let container = NSTextContainer(
    size: NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude))
  container.widthTracksTextView = true
  layout.textContainer = container
  let editor = NSTextView(
    frame: NSRect(x: 0, y: 0, width: 900, height: 500), textContainer: container)
  editor.isRichText = false
  editor.font = font
  guard editor.textLayoutManager === layout, editor.textContentStorage === chunked else {
    throw NSError(domain: "probe", code: 1)
  }

  let total = originalStorage.length
  let start: Int
  switch target {
  case "start": start = header.utf16.count
  case "middle": start = total / 2
  case "end": start = max(0, total - 128)
  default: start = 0
  }
  let length = min(target == "header" ? header.utf16.count : 1_024, total - start)
  guard let startLocation = chunked.location(chunked.documentRange.location, offsetBy: start),
    let endLocation = chunked.location(chunked.documentRange.location, offsetBy: start + length),
    let targetRange = NSTextRange(location: startLocation, end: endLocation)
  else { throw NSError(domain: "probe", code: 3) }
  layout.ensureLayout(for: targetRange)

  var rows: [String] = []
  var covered = start
  _ = layout.enumerateTextLayoutFragments(from: startLocation, options: [.ensuresLayout]) {
    fragment in
    guard let fragmentStart = fragment.textElement?.elementRange?.location else { return false }
    let elementStart = chunked.offset(from: chunked.documentRange.location, to: fragmentStart)
    for line in fragment.textLineFragments {
      let lineStart = elementStart + line.characterRange.location
      rows.append(
        "\(lineStart):\(line.characterRange.length):\(line.typographicBounds.width.bitPattern)")
    }
    for row in rows {
      let fields = row.split(separator: ":")
      guard fields.count == 3, let lineStart = Int(fields[0]), let lineLength = Int(fields[1])
      else { continue }
      if lineStart <= covered && lineStart + lineLength > covered {
        covered = lineStart + lineLength
      }
    }
    return covered < start + length
  }

  let before = editor.string
  let beforeSelection = editor.selectedRange()
  editor.insertText("X", replacementRange: NSRange(location: 0, length: 0))
  let editPreserved =
    editor.string.utf16.count == before.utf16.count + 1
    && editor.string.utf16.first == 88
    && editor.string.utf16.dropFirst().elementsEqual(before.utf16)
  let afterEdit = editor.string
  if editor.undoManager?.canUndo == true { editor.undoManager?.undo() }
  let undoPreserved = editor.string == before
  let result: [String: Any] = [
    "requestedBytes": bytes,
    "actualBytes": before.utf8.count,
    "sourceUTF16": total,
    "chunkUTF16": chunkUnits,
    "target": target,
    "targetRangeUTF16": [start, length],
    "coveredThroughUTF16": covered,
    "targetCovered": covered >= start + length,
    "geometrySHA256": SHA256.hash(data: Data(rows.joined(separator: ";").utf8)).map {
      String(format: "%02x", $0)
    }.joined(),
    "elementCount": chunked.emitted,
    "textStorageIdentityPreserved": editor.textStorage === originalStorage,
    "managerAttached": editor.textContentStorage === chunked,
    "textBeforeEditSHA256": SHA256.hash(data: Data(before.utf8)).map {
      String(format: "%02x", $0)
    }.joined(),
    "editPreserved": editPreserved,
    "undoPreserved": undoPreserved,
    "selectionBeforeEdit": [beforeSelection.location, beforeSelection.length],
    "selectionAfterUndo": [editor.selectedRange().location, editor.selectedRange().length],
    "postEditBytes": afterEdit.utf8.count,
  ]
  return result
}

let args = Array(CommandLine.arguments.dropFirst())
let result = try run(
  bytes: Int(args.first ?? "10485760") ?? 10_485_760,
  chunkUnits: Int(args.dropFirst().first ?? "4032") ?? 4032,
  target: args.dropFirst(2).first ?? "middle")
print(
  String(
    decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
    as: UTF8.self))
