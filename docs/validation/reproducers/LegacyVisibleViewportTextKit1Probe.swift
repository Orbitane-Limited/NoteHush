import AppKit
import CryptoKit
import Foundation

@MainActor
func run() throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let header = "123456789012345\n"
  let unit = "خط📝"
  let byteCount = 10_485_760
  let repetitions = (byteCount - header.utf8.count) / unit.utf8.count
  let text = header + String(repeating: unit, count: repetitions)
  let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  let paragraph = NSMutableParagraphStyle()
  paragraph.baseWritingDirection = .natural
  let attributed = NSAttributedString(
    string: text, attributes: [.font: font, .paragraphStyle: paragraph])
  let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
  scroll.hasVerticalScroller = true
  scroll.hasHorizontalScroller = false
  let view = NSTextView(usingTextLayoutManager: false)
  view.frame = NSRect(x: 0, y: 0, width: 868, height: 500)
  view.isRichText = false
  view.font = font
  view.textContainerInset = NSSize(width: 16, height: 16)
  view.isVerticallyResizable = true
  view.isHorizontallyResizable = false
  scroll.documentView = view
  view.layoutSubtreeIfNeeded()
  guard let storage = view.textStorage, let container = view.textContainer,
    let layout = view.layoutManager
  else {
    throw NSError(domain: "legacy-visible", code: 1)
  }
  container.widthTracksTextView = true
  container.containerSize = NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude)
  layout.allowsNonContiguousLayout = true
  layout.backgroundLayoutEnabled = true
  let assignStart = ProcessInfo.processInfo.systemUptime
  storage.setAttributedString(attributed)
  let assignDuration = ProcessInfo.processInfo.systemUptime - assignStart
  print("stage=assigned seconds=\(assignDuration)")
  fflush(stdout)
  scroll.contentView.setBoundsOrigin(.zero)
  scroll.layoutSubtreeIfNeeded()
  let queryStart = ProcessInfo.processInfo.systemUptime
  let visibleGlyphs = layout.glyphRange(forBoundingRect: scroll.contentView.bounds, in: container)
  let queryDuration = ProcessInfo.processInfo.systemUptime - queryStart
  print("stage=visible-range seconds=\(queryDuration) range=\(NSStringFromRange(visibleGlyphs))")
  fflush(stdout)
  let ensureStart = ProcessInfo.processInfo.systemUptime
  layout.ensureLayout(forGlyphRange: visibleGlyphs)
  let ensureDuration = ProcessInfo.processInfo.systemUptime - ensureStart
  print("stage=ensure-visible seconds=\(ensureDuration)")
  fflush(stdout)
  var lines = 0
  var utf16 = 0
  layout.enumerateLineFragments(forGlyphRange: visibleGlyphs) { _, _, _, glyphRange, _ in
    lines += 1
    utf16 += layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil).length
  }
  print(
    "fixtureBytes=\(text.utf8.count) digest=\(digest) assignedUTF16=\(storage.length) assignSeconds=\(assignDuration) querySeconds=\(queryDuration) ensureSeconds=\(ensureDuration) glyphCount=\(layout.numberOfGlyphs) visibleGlyphRange=\(NSStringFromRange(visibleGlyphs)) visibleLineCount=\(lines) visibleCharacterCount=\(utf16) completeLayout=\(layout.isValidGlyphIndex(layout.numberOfGlyphs - 1))"
  )
}

@main @MainActor enum Main {
  static func main() throws { try run() }
}
