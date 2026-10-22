import AppKit

@MainActor
final class RangeDelegate: NSObject, @MainActor NSTextLayoutManagerDelegate {
  let variant: String
  var calls: [[String: Int]] = []
  init(variant: String) { self.variant = variant }

  func textLayoutManager(
    _ manager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
    in element: NSTextElement
  ) -> NSTextLayoutFragment {
    guard let content = manager.textContentManager, let elementRange = element.elementRange,
      let paragraph = element as? NSTextParagraph else { preconditionFailure("Missing generated paragraph") }
    let start = content.offset(from: elementRange.location, to: location)
    let count = paragraph.attributedString.length
    precondition(start >= 0 && start <= count)
    let length = variant == "partial" ? min(4096, count - start) : count
    let origin = variant == "partial" ? location : elementRange.location
    guard let end = content.location(origin, offsetBy: length),
      let range = NSTextRange(location: origin, end: end) else { preconditionFailure("Invalid generated range") }
    calls.append(["requestedOffset": start, "paragraphUTF16": count, "returnedLength": length])
    return NSTextLayoutFragment(textElement: element, range: range)
  }
}

@main
@MainActor
enum TextKitFragmentRangeProbe {
  static func record(_ value: [String: Any]) throws {
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: value) + Data([10]))
  }
  static func main() throws {
    guard CommandLine.arguments.count == 3,
      let bytes = Int(CommandLine.arguments[1]), [16384, 262144, 1048576].contains(bytes),
      ["native", "partial"].contains(CommandLine.arguments[2]) else { exit(EX_CONFIG) }
    let variant = CommandLine.arguments[2]
    let text = String(repeating: "خط📝", count: bytes / 8)
    let paragraph = NSMutableParagraphStyle()
    paragraph.baseWritingDirection = .natural
    let original = NSAttributedString(string: text, attributes: [
      .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .paragraphStyle: paragraph,
    ])
    try record(["phase": "beforeStorage", "bytes": bytes, "variant": variant, "utf16": original.length])
    let storage = NSTextStorage()
    let content = NSTextContentStorage()
    content.textStorage = storage
    let layout = NSTextLayoutManager()
    content.addTextLayoutManager(layout)
    layout.textContainer = NSTextContainer(size: NSSize(width: 900, height: CGFloat.greatestFiniteMagnitude))
    let delegate = RangeDelegate(variant: variant)
    layout.delegate = delegate
    content.performEditingTransaction { storage.setAttributedString(original) }
    let documentLength = content.offset(from: content.documentRange.location, to: content.documentRange.endLocation)
    guard documentLength == original.length else {
      try record(["phase": "invalidInitialDocumentLength", "observedUTF16": documentLength])
      exit(65)
    }
    try record(["phase": "beforeLayout", "bytes": bytes, "variant": variant, "utf16": original.length])
    layout.ensureLayout(for: content.documentRange)
    try record(["phase": "layoutReturned", "delegateCalls": delegate.calls])
    var fragments: [[String: Any]] = []
    var covered = 0
    var valid = true
    let originalString = text as NSString
    _ = layout.enumerateTextLayoutFragments(from: content.documentRange.location, options: []) { fragment in
      let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
      let end = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.endLocation)
      var row: [String: Any] = ["start": start, "end": end, "state": fragment.state.rawValue]
      if fragment.state == .layoutAvailable {
        let lines = fragment.textLineFragments
        var lineRows: [[String: Any]] = []
        for line in lines {
          let source = line.attributedString
          let local = line.characterRange
          let origin: Int?
          if source.length == original.length { origin = 0 }
          else if source.length == end - start { origin = start }
          else { origin = nil }
          var lineRow: [String: Any] = ["start": local.location, "length": local.length,
            "sourceUTF16": source.length,
            "localBounds": [line.typographicBounds.minX, line.typographicBounds.minY,
                            line.typographicBounds.width, line.typographicBounds.height]]
          guard let origin, local.location <= source.length,
            local.length <= source.length - local.location else {
            valid = false
            lineRow["mappingValid"] = false
            lineRows.append(lineRow)
            continue
          }
          let global = NSRange(location: origin + local.location, length: local.length)
          let bounds = line.typographicBounds.offsetBy(
            dx: fragment.layoutFragmentFrame.minX, dy: fragment.layoutFragmentFrame.minY)
          lineRow["globalStart"] = global.location
          lineRow["bounds"] = [bounds.minX, bounds.minY, bounds.width, bounds.height]
          let inside = global.location >= start && NSMaxRange(global) <= end
            && NSMaxRange(global) <= original.length
          lineRow["mappingValid"] = inside
          if inside {
            // Total compared text is linear in document length, not one full document per line.
            let actualText = source.attributedSubstring(from: local).string
            let expectedText = originalString.substring(with: global)
            let exactLine = actualText.utf16.elementsEqual(expectedText.utf16)
            lineRow["exactLineText"] = exactLine
            if !exactLine || global.location != covered { valid = false }
            covered = NSMaxRange(global)
          } else { valid = false }
          lineRows.append(lineRow)
        }
        row["lines"] = lineRows
      } else { valid = false }
      fragments.append(row)
      if fragments.count > original.length + 1 { valid = false; return false }
      return true
    }
    let exact = storage.string.utf16.elementsEqual(text.utf16)
    let complete = valid && exact && covered == original.length && !fragments.isEmpty
    try record(["phase": "coverage", "fragments": fragments, "coveredUTF16": covered,
                "exactText": exact, "exactAttributedText": storage.isEqual(to: original), "completeCoverage": complete,
                "geometryEquivalenceVerified": false, "delegateCalls": delegate.calls])
    withExtendedLifetime(delegate) { layout.delegate = nil }
    if !complete { exit(65) }
  }
}
