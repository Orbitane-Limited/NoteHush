@preconcurrency import AppKit
import os
import CryptoKit
import Foundation

@MainActor final class ChunkedTextContentStorage: NSTextContentStorage {
  let chunkUnits: Int
  nonisolated private let emittedCounter = OSAllocatedUnfairLock(initialState: 0)
  var emitted: Int { emittedCounter.withLock { $0 } }
  nonisolated private let offsetLock = OSAllocatedUnfairLock(initialState: [ObjectIdentifier: Int]())

  nonisolated private func remember(_ location: any NSTextLocation, offset: Int) {
    offsetLock.withLock { $0[ObjectIdentifier(location as AnyObject)] = offset }
  }

  nonisolated private func rememberedOffset(_ location: any NSTextLocation) -> Int? {
    offsetLock.withLock { $0[ObjectIdentifier(location as AnyObject)] }
  }

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
    let total = super.offset(from: documentStart, to: documentEnd)
    remember(documentStart, offset: 0)
    remember(documentEnd, offset: total)
    let requested =
      textLocation.map { offset(from: documentStart, to: $0) }
      ?? (options.contains(.reverse) ? total : 0)
    guard total >= 0, requested >= 0 else { return nil }

    func location(_ offset: Int) -> (any NSTextLocation)? {
      guard let value = super.location(documentStart, offsetBy: offset) else { return nil }
      remember(value, offset: offset)
      return value
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
        emittedCounter.withLock { $0 += 1 }
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
      let end = min(total, start + chunkUnits)
      guard let startLocation = location(start), let endLocation = location(end),
        let elementRange = NSTextRange(location: startLocation, end: endLocation)
      else { return nil }
      let attributed = textStorage.attributedSubstring(
        from: NSRange(location: start, length: end - start))
      let paragraph = NSTextParagraph(attributedString: attributed)
      paragraph.textContentManager = self
      paragraph.elementRange = elementRange
      emittedCounter.withLock { $0 += 1 }
      if !block(paragraph) { return endLocation }
      lastEnd = end
      start = end
    }
    return location(lastEnd)
  }

  override func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (
    any NSTextLocation
  )? {
    let base = rememberedOffset(location)
      ?? super.offset(from: documentRange.location, to: location)
    guard base != NSNotFound, let result = super.location(location, offsetBy: offset) else {
      return nil
    }
    remember(result, offset: base + offset)
    return result
  }

  override func offset(from: any NSTextLocation, to: any NSTextLocation) -> Int {
    guard let start = rememberedOffset(from),
      let end = rememberedOffset(to)
    else { return NSNotFound }
    return end - start
  }
}

@MainActor func run(bytes: Int, chunkUnits: Int, target: String) throws -> [String: Any] {
  let unit = "خط📝"
  let header = "123456789012345"
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
  fputs("stage=before-editor-init\n", stderr)
  let editor = NSTextView(
    frame: NSRect(x: 0, y: 0, width: 900, height: 500), textContainer: container)
  editor.isRichText = false
  editor.allowsUndo = true
  editor.textContainerInset = NSSize(width: 16, height: 16)
  editor.font = font
  NSApplication.shared.setActivationPolicy(.prohibited)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
    styleMask: .borderless, backing: .buffered, defer: false)
  window.contentView = editor
  let becameFirstResponder = window.makeFirstResponder(editor)
  fputs("windowAttached=\(editor.window != nil) firstResponder=\(becameFirstResponder)\n", stderr)
  fputs("stage=after-editor-init\n", stderr)
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
  let length = min(target == "header" ? header.utf16.count : (target == "full" ? total : 1_024), total - start)
  guard let startLocation = chunked.location(chunked.documentRange.location, offsetBy: start),
    let endLocation = chunked.location(chunked.documentRange.location, offsetBy: start + length),
    let targetRange = NSTextRange(location: startLocation, end: endLocation)
  else { throw NSError(domain: "probe", code: 3) }
  fputs("stage=before-ensure\n", stderr)
  layout.ensureLayout(for: targetRange)
  fputs("stage=after-ensure\n", stderr)

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

  var baselineRows: [String] = []
  if target == "full" && bytes <= 1_048_576 {
    let baselineEditor = NSTextView(usingTextLayoutManager: true)
    baselineEditor.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
    baselineEditor.isRichText = false
    baselineEditor.textContainerInset = NSSize(width: 16, height: 16)
    baselineEditor.font = font
    guard let baselineStorage = baselineEditor.textStorage,
      let baselineLayout = baselineEditor.textLayoutManager,
      let baselineContent = baselineEditor.textContentStorage,
      let baselineContainer = baselineLayout.textContainer
    else { throw NSError(domain: "probe", code: 20) }
    baselineStorage.setAttributedString(source)
    baselineContainer.widthTracksTextView = true
    baselineContainer.containerSize = NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude)
    baselineLayout.ensureLayout(for: baselineLayout.documentRange)
    _ = baselineLayout.enumerateTextLayoutFragments(
      from: baselineLayout.documentRange.location, options: [.ensuresLayout]
    ) { fragment in
      guard let elementRange = fragment.textElement?.elementRange else { return false }
      let base = baselineContent.offset(
        from: baselineContent.documentRange.location, to: elementRange.location)
      for line in fragment.textLineFragments {
        baselineRows.append(
          "\(base + line.characterRange.location):\(line.characterRange.length):\(line.typographicBounds.width.bitPattern)"
        )
      }
      return true
    }
  }
  if bytes > 1_048_576 || target == "full" {
    return [
      "requestedBytes": bytes,
      "actualBytes": text.utf8.count,
      "sourceUTF16": total,
      "target": target,
      "targetRangeUTF16": [start, length],
      "coveredThroughUTF16": covered,
      "targetCovered": covered >= start + length,
      "rows": rows,
      "baselineRows": baselineRows,
      "nativeGeometryMatches": baselineRows.isEmpty ? NSNull() : (baselineRows == rows),
      "geometrySHA256": SHA256.hash(data: Data(rows.joined(separator: ";").utf8)).map {
        String(format: "%02x", $0)
      }.joined(),
      "elementCount": chunked.emitted,
      "managerAttached": editor.textContentStorage === chunked,
    ]
  }
  let before = editor.string
  let beforeSelection = editor.selectedRange()
  let insertion = header.utf16.count + (chunkUnits / 5) * 5
  editor.insertText("X", replacementRange: NSRange(location: insertion, length: 0))
  layout.ensureLayout(for: layout.documentRange)
  var postEditLineCount = 0
  _ = layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
    postEditLineCount += fragment.textLineFragments.count
    return true
  }
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
    "postEditLineCount": postEditLineCount,
    "editInsertionUTF16": insertion,
  ]
  return result
}

@main @MainActor
enum Probe {
  static func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    let result = try run(
      bytes: Int(args.first ?? "10485760") ?? 10_485_760,
      chunkUnits: Int(args.dropFirst().first ?? "4032") ?? 4032,
      target: args.dropFirst(2).first ?? "middle")
    print(
      String(
        decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
        as: UTF8.self))
  }
}
