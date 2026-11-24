import AppKit
import CryptoKit
import Foundation

@main
@MainActor
enum TextKitLayoutQueueViewportProbe {
  static func main() {
    NSApplication.shared.setActivationPolicy(.prohibited)
    Probe().run()
  }
}

@MainActor
private final class Probe: NSObject {
  private let editor = NSTextView(usingTextLayoutManager: true)
  private let queue = OperationQueue()
  private var timer: Timer?
  private var request: Timer?
  private var began = ContinuousClock.now

  func run() {
    guard let layout = editor.textLayoutManager, let container = editor.textContainer,
      let storage = editor.textStorage
    else { fatalError("TextKit 2 unavailable") }
    queue.name = "generated-layout-control"
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .userInitiated
    layout.layoutQueue = queue
    editor.isRichText = false
    editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
    editor.textContainerInset = NSSize(width: 16, height: 16)
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    container.widthTracksTextView = true
    container.containerSize = NSSize(width: 868, height: CGFloat.greatestFiniteMagnitude)
    let text = "123456789012345\n" + String(repeating: "خط📝", count: (10_485_760 - 16) / 8)
    precondition(text.utf8.count == 10_485_760)
    let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    editor.string = text
    precondition(storage.length == text.utf16.count)
    began = .now
    timer = Timer(
      timeInterval: 0.1, target: self, selector: #selector(heartbeat(_:)), userInfo: digest,
      repeats: true)
    request = Timer(
      timeInterval: 0.2, target: self, selector: #selector(layoutViewport(_:)), userInfo: layout,
      repeats: false)
    if let timer { RunLoop.main.add(timer, forMode: .common) }
    if let request { RunLoop.main.add(request, forMode: .common) }
    let deadline = Date(timeIntervalSinceNow: 10)
    while Date() < deadline {
      _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    }
    timer?.invalidate()
    request?.invalidate()
    fputs(
      "probe-ended layoutQueue=\(layout.layoutQueue != nil) queued=\(queue.operationCount) bytes=\(storage.string.utf8.count)\n",
      stderr)
  }

  @objc private func heartbeat(_ timer: Timer) {
    let elapsed = began.duration(to: .now).components
    let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    let digest = timer.userInfo as? String ?? ""
    fputs("heartbeat elapsed=\(seconds) queue=\(queue.operationCount) sha256=\(digest)\n", stderr)
  }

  @objc private func layoutViewport(_ timer: Timer) {
    guard let layout = timer.userInfo as? NSTextLayoutManager else { return }
    fputs("before-layoutViewport queue=\(queue.operationCount)\n", stderr)
    layout.textViewportLayoutController.layoutViewport()
    fputs("after-layoutViewport queue=\(queue.operationCount)\n", stderr)
    CFRunLoopStop(CFRunLoopGetMain())
  }
}
