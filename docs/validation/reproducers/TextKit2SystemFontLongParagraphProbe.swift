import AppKit
import CryptoKit
import Foundation

@main @MainActor enum Main {
  static func main() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let header = "123456789012345\n"
    let unit = "خط📝"
    let target = 10_485_760
    let text =
      header + String(repeating: unit, count: (target - header.utf8.count) / unit.utf8.count)
    let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    let font = NSFont.systemFont(ofSize: 14)
    let paragraph = NSMutableParagraphStyle()
    paragraph.baseWritingDirection = .natural
    let source = NSAttributedString(
      string: text, attributes: [.font: font, .paragraphStyle: paragraph])
    let view = NSTextView(usingTextLayoutManager: true)
    view.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
    view.isRichText = false
    view.font = font
    view.textContainerInset = NSSize(width: 16, height: 16)
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    guard let storage = view.textStorage, let container = view.textContainer,
      let layout = view.textLayoutManager
    else {
      throw NSError(domain: "system-font", code: 1)
    }
    container.widthTracksTextView = true
    container.containerSize = NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude)
    let assignStart = ProcessInfo.processInfo.systemUptime
    storage.setAttributedString(source)
    let assignTime = ProcessInfo.processInfo.systemUptime - assignStart
    print(
      "stage=assigned seconds=\(assignTime) bytes=\(text.utf8.count) digest=\(digest) utf16=\(storage.length)"
    )
    fflush(stdout)
    guard
      let range = NSTextRange(
        location: layout.documentRange.location, end: layout.documentRange.endLocation)
    else {
      throw NSError(domain: "system-font", code: 2)
    }
    let layoutStart = ProcessInfo.processInfo.systemUptime
    layout.ensureLayout(for: range)
    let layoutTime = ProcessInfo.processInfo.systemUptime - layoutStart
    var lines = 0
    var coverage = 0
    _ = layout.enumerateTextLayoutFragments(from: range.location, options: []) { fragment in
      for line in fragment.textLineFragments {
        lines += 1
        coverage += line.characterRange.length
      }
      return true
    }
    print(
      "layoutSeconds=\(layoutTime) lineCount=\(lines) utf16Coverage=\(coverage) sourceUTF16=\(storage.length) complete=\(coverage == storage.length)"
    )
  }
}
