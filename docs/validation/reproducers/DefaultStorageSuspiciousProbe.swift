@preconcurrency import AppKit
import CryptoKit
import Foundation

@main @MainActor enum Probe {
  static func main() {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let arguments = Array(CommandLine.arguments.dropFirst())
    let limitSuspicious = arguments.first == "true"
    let byteCount = Int(arguments.dropFirst().first ?? "10485760") ?? 10_485_760
    let unit = "خط📝"
    let header = "123456789012345\n"
    let repetitions = max(1, (byteCount - header.utf8.count) / unit.utf8.count)
    let text = header + String(repeating: unit, count: repetitions)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.baseWritingDirection = .natural
    let source = NSAttributedString(
      string: text,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
        .paragraphStyle: paragraphStyle,
      ])

    let editor = NSTextView(usingTextLayoutManager: true)
    editor.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
    editor.isRichText = false
    editor.textContainerInset = NSSize(width: 16, height: 16)
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    guard let storage = editor.textStorage,
      let layoutManager = editor.textLayoutManager,
      let textContainer = editor.textContainer
    else {
      fputs("error=TextKit2 construction failed\n", stderr)
      exit(2)
    }
    layoutManager.limitsLayoutForSuspiciousContents = limitSuspicious
    textContainer.containerSize = NSSize(
      width: 858, height: CGFloat.greatestFiniteMagnitude)
    print(
      "stage=constructed limit=\(limitSuspicious) bytes=\(text.utf8.count) utf16=\(source.length)")
    fflush(stdout)

    let assignmentStart = ProcessInfo.processInfo.systemUptime
    storage.setAttributedString(source)
    print("stage=assigned seconds=\(ProcessInfo.processInfo.systemUptime - assignmentStart)")
    fflush(stdout)

    let layoutStart = ProcessInfo.processInfo.systemUptime
    layoutManager.ensureLayout(for: CGRect(x: 0, y: 0, width: 858, height: 600))
    let layoutSeconds = ProcessInfo.processInfo.systemUptime - layoutStart
    print("stage=viewport seconds=\(layoutSeconds)")
    fflush(stdout)
    let digest = SHA256.hash(data: Data(text.utf8)).map {
      String(format: "%02x", $0)
    }.joined()
    print(
      "result=digest:\(digest) assignedUTF16:\(storage.length) layoutSeconds:\(layoutSeconds)")
  }
}
