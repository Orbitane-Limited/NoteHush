import AppKit
import CoreFoundation

@MainActor
final class ProbePresenter: NSObject, @MainActor NSTextContentStorageDelegate {
  func textContentStorage(_ content: NSTextContentStorage, textParagraphWith range: NSRange)
    -> NSTextParagraph?
  {
    guard let storage = content.textStorage, range.length > 0 else { return nil }
    let original = storage.attributedSubstring(from: range)
    let style =
      (original.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?
      .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
    guard style.baseWritingDirection == .natural else { return nil }
    guard #available(macOS 26.0, *) else { return nil }
    var levels = [UInt8](repeating: 253, count: range.length)
    var directions = [UInt8](repeating: 253, count: range.length)
    levels.withUnsafeMutableBufferPointer { levelBuffer in
      directions.withUnsafeMutableBufferPointer { directionBuffer in
        _ = CFAttributedStringGetStatisticalWritingDirections(
          original as CFAttributedString, CFRange(location: 0, length: range.length), -1,
          levelBuffer.baseAddress, directionBuffer.baseAddress)
      }
    }
    guard let base = directions.first, base == 0 || base == 1, directions.allSatisfy({ $0 == base })
    else { return nil }
    style.baseWritingDirection = base == 0 ? .leftToRight : .rightToLeft
    let presented = NSMutableAttributedString(attributedString: original)
    presented.addAttribute(
      .paragraphStyle, value: style, range: NSRange(location: 0, length: presented.length))
    fputs("resolved count=\(range.length) direction=\(base)\n", stderr)
    return NSTextParagraph(attributedString: presented)
  }
}

@MainActor
func run() throws {
  let bytes = 10_485_760
  let header = "123456789012345\n"
  let text = header + String(repeating: "خط📝", count: (bytes - header.utf8.count) / 8)
  precondition(text.utf8.count == bytes)
  let style = NSMutableParagraphStyle()
  style.baseWritingDirection = .natural
  let storage = NSTextStorage(
    attributedString: NSAttributedString(
      string: text,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .paragraphStyle: style,
      ]))
  let editor = NSTextView(usingTextLayoutManager: true)
  editor.frame = NSRect(x: 0, y: 0, width: 868, height: 500)
  guard let content = editor.textLayoutManager?.textContentManager as? NSTextContentStorage else {
    fatalError("no content storage")
  }
  let presenter = ProbePresenter()
  content.delegate = presenter
  editor.textContainerInset = NSSize(width: 5, height: 5)
  let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 868, height: 500))
  scroll.documentView = editor
  let before = ProcessInfo.processInfo.systemUptime
  editor.textStorage?.setAttributedString(storage)
  fputs("assigned elapsed=\(ProcessInfo.processInfo.systemUptime - before)\n", stderr)
  guard let layout = editor.textLayoutManager, let manager = layout.textContentManager else {
    fatalError("missing manager")
  }
  let a = manager.documentRange.location
  let b = manager.location(a, offsetBy: 2048)!
  let range = NSTextRange(location: a, end: b)!
  let layoutStart = ProcessInfo.processInfo.systemUptime
  layout.ensureLayout(for: range)
  fputs(
    "viewport elapsed=\(ProcessInfo.processInfo.systemUptime - layoutStart) fragments=\(layout.textLayoutFragment(for: a)?.textLineFragments.count ?? 0) total=\(ProcessInfo.processInfo.systemUptime - before)\n",
    stderr)
  withExtendedLifetime((scroll, presenter)) {}
}

@main @MainActor enum Main {
  static func main() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    try run()
  }
}
