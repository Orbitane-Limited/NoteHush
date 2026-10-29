import AppKit
import CryptoKit
import Foundation

@MainActor
final class BreakDelegate: NSObject, @preconcurrency NSTextLayoutManagerDelegate {
  let stride: Int
  var calls = 0
  var breaks = 0
  init(stride: Int) { self.stride = stride }

  func textLayoutManager(
    _ textLayoutManager: NSTextLayoutManager,
    shouldBreakLineBefore location: any NSTextLocation,
    hyphenating: Bool
  ) -> Bool {
    calls += 1
    if calls == 1 || calls.isMultiple(of: 1000) { fputs("break-callbacks=\(calls)\n", stderr) }
    guard let content = textLayoutManager.textContentManager else { return false }
    let offset = content.offset(from: content.documentRange.location, to: location)
    if offset > 0 && offset % stride == 0 {
      breaks += 1
      return true
    }
    return false
  }
}

@main @MainActor
enum Probe {
  static func main() {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let requestedBytes = Int(CommandLine.arguments.dropFirst().first ?? "16384") ?? 16384
    let stride = Int(CommandLine.arguments.dropFirst(2).first ?? "128") ?? 128
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
    view.textStorage?.setAttributedString(attributed)
    fputs("stage=assigned bytes=\(text.utf8.count)\n", stderr)
    fflush(stderr)
    let delegate = BreakDelegate(stride: stride)
    view.textLayoutManager!.delegate = delegate
    let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    let start = ProcessInfo.processInfo.systemUptime
    view.textLayoutManager!.ensureLayout(for: CGRect(x: 0, y: 0, width: 858, height: 600))
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    print(
      "bytes=\(text.utf8.count) utf16=\(attributed.length) digest=\(digest) stride=\(stride) elapsed=\(elapsed) delegateCalls=\(delegate.calls) forcedBreaks=\(delegate.breaks) actualTextPreserved=\(view.string == text) fragment=\(String(describing: view.textLayoutManager!.textLayoutFragment(for: view.textLayoutManager!.documentRange.location)?.state))"
    )
  }
}
