import AppKit
import CryptoKit
import Foundation

final class ChunkParagraphDelegate: NSObject, NSTextContentStorageDelegate {
  let chunkUnits: Int
  private(set) var emitted = 0
  private(set) var requestedOffsets: [Int] = []

  init(chunkUnits: Int) {
    self.chunkUnits = chunkUnits
  }

  func textContentManager(
    _ textContentManager: NSTextContentManager,
    textElementAt location: any NSTextLocation
  ) -> NSTextElement? {
    guard let storageManager = textContentManager as? NSTextContentStorage,
      let storage = storageManager.textStorage
    else { return nil }
    let documentStart = storageManager.documentRange.location
    let total = storage.length
    let offset = storageManager.offset(from: documentStart, to: location)
    requestedOffsets.append(offset)
    guard (0..<total).contains(offset) else { return nil }
    let start = (offset / chunkUnits) * chunkUnits
    let end = min(total, start + chunkUnits)
    guard start < end,
      let startLocation = storageManager.location(documentStart, offsetBy: start),
      let endLocation = storageManager.location(documentStart, offsetBy: end),
      let range = NSTextRange(location: startLocation, end: endLocation)
    else { return nil }
    let attributed = storage.attributedSubstring(
      from: NSRange(location: start, length: end - start))
    let paragraph = NSTextParagraph(attributedString: attributed)
    paragraph.textContentManager = storageManager
    paragraph.elementRange = range
    emitted += 1
    return paragraph
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

  let editor = NSTextView(usingTextLayoutManager: true)
  editor.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
  editor.isRichText = false
  editor.font = font
  editor.textContainer?.containerSize = NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude)
  editor.textContainer?.widthTracksTextView = true
  guard let layout = editor.textLayoutManager, let storage = editor.textStorage,
    let manager = editor.textContentStorage
  else { throw NSError(domain: "probe", code: 1) }
  let delegate = ChunkParagraphDelegate(chunkUnits: chunkUnits)
  manager.delegate = delegate
  storage.setAttributedString(source)

  let total = storage.length
  let start: Int
  switch target {
  case "start": start = header.utf16.count
  case "middle": start = total / 2
  case "end": start = max(0, total - 128)
  default: start = 0
  }
  let length = min(target == "header" ? header.utf16.count : 1_024, total - start)
  guard let startLocation = manager.location(manager.documentRange.location, offsetBy: start),
    let endLocation = manager.location(manager.documentRange.location, offsetBy: start + length),
    let targetRange = NSTextRange(location: startLocation, end: endLocation)
  else { throw NSError(domain: "probe", code: 2) }
  layout.ensureLayout(for: targetRange)

  var rows: [String] = []
  var fragmentStates: [UInt] = []
  var fragmentRanges: [[Int]] = []
  var covered = start
  _ = layout.enumerateTextLayoutFragments(from: startLocation, options: [.ensuresLayout]) {
    fragment in
    fragmentStates.append(fragment.state.rawValue)
    guard let fragmentStart = fragment.textElement?.elementRange?.location else { return false }
    let elementStart = manager.offset(from: manager.documentRange.location, to: fragmentStart)
    if let elementRange = fragment.textElement?.elementRange {
      let elementEnd = manager.offset(
        from: manager.documentRange.location, to: elementRange.endLocation)
      fragmentRanges.append([elementStart, elementEnd, fragment.textLineFragments.count])
    }
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

  let original = editor.string
  let selectionBeforeEdit = editor.selectedRange()
  editor.insertText("X", replacementRange: NSRange(location: 0, length: 0))
  let editPreserved =
    editor.string.utf16.count == original.utf16.count + 1
    && editor.string.utf16.first == 88
    && editor.string.utf16.dropFirst().elementsEqual(original.utf16)
  let undoManager = editor.undoManager
  if undoManager?.canUndo == true { undoManager?.undo() }
  return [
    "requestedBytes": bytes,
    "actualBytes": original.utf8.count,
    "sourceUTF16": total,
    "chunkUTF16": chunkUnits,
    "target": target,
    "targetRangeUTF16": [start, length],
    "coveredThroughUTF16": covered,
    "targetCovered": covered >= start + length,
    "geometrySHA256": SHA256.hash(data: Data(rows.joined(separator: ";").utf8)).map {
      String(format: "%02x", $0)
    }.joined(),
    "elementCount": delegate.emitted,
    "delegateRequestedOffsets": delegate.requestedOffsets,
    "fragmentStates": fragmentStates,
    "fragmentRangesAndLineCounts": fragmentRanges,
    "textStorageIdentityPreserved": editor.textStorage === storage,
    "contentStorageUnchanged": editor.textContentStorage === manager,
    "textBeforeEditSHA256": SHA256.hash(data: Data(original.utf8)).map {
      String(format: "%02x", $0)
    }.joined(),
    "editPreserved": editPreserved,
    "undoManagerAvailable": undoManager != nil,
    "undoPreserved": editor.string == original,
    "selectionBeforeEdit": [selectionBeforeEdit.location, selectionBeforeEdit.length],
    "selectionAfterEdit": [editor.selectedRange().location, editor.selectedRange().length],
  ]
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
