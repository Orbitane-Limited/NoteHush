import AppKit
import CryptoKit
import Foundation

@main @MainActor
enum Probe {
  static func main() {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let requestedBytes = Int(CommandLine.arguments.dropFirst().first ?? "16384") ?? 16384
    let header = "123456789012345\n"
    let unit = "خط📝"
    let count = max(1, (requestedBytes - header.utf8.count) / unit.utf8.count)
    let text = header + String(repeating: unit, count: count)
    let style = NSMutableParagraphStyle()
    style.baseWritingDirection = .natural
    let attributed = NSAttributedString(
      string: text,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .paragraphStyle: style,
      ])
    let view = NSTextView(usingTextLayoutManager: true)
    view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
    view.isRichText = false
    view.textContainerInset = NSSize(width: 16, height: 16)
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    scroll.documentView = view
    view.layoutSubtreeIfNeeded()
    view.textLayoutManager!.textContainer!.containerSize = NSSize(
      width: 858, height: CGFloat.greatestFiniteMagnitude)
    view.textLayoutManager!.textContainer!.lineBreakMode = .byCharWrapping
    view.textStorage?.setAttributedString(attributed)
    fputs("stage=assigned bytes=\(text.utf8.count)\n", stderr)
    fflush(stderr)
    let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    let start = ProcessInfo.processInfo.systemUptime
    view.textLayoutManager!.ensureLayout(for: CGRect(x: 0, y: 0, width: 858, height: 600))
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    print(
      "bytes=\(text.utf8.count) utf16=\(attributed.length) digest=\(digest) wrapMode=byCharWrapping elapsed=\(elapsed) actualTextPreserved=\(view.string == text) fragment=\(String(describing: view.textLayoutManager!.textLayoutFragment(for: view.textLayoutManager!.documentRange.location)?.state))"
    )
  }
}
