import AppKit
import CryptoKit
import Foundation

@MainActor
final class FragmentQueueDelegate: NSObject, @MainActor NSTextLayoutManagerDelegate {
  let queue = OperationQueue()

  override init() {
    super.init()
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .userInitiated
  }

  func textLayoutManager(
    _ manager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
    in element: NSTextElement
  ) -> NSTextLayoutFragment {
    let fragment = NSTextLayoutFragment(textElement: element, range: element.elementRange)
    if let paragraph = element as? NSTextParagraph, paragraph.attributedString.length > 8192 {
      fragment.layoutQueue = queue
    }
    return fragment
  }
}

@main
@MainActor
enum TextKitFragmentQueueCompletionProbe {
  static func main() {
    guard CommandLine.arguments.count == 2,
      let byteCount = Int(CommandLine.arguments[1]),
      byteCount == 10_485_760
    else { exit(EX_CONFIG) }

    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    do {
      try Probe(byteCount: byteCount).run()
    } catch {
      FileHandle.standardError.write(Data("probe failed: \(error)\n".utf8))
      exit(1)
    }
  }
}

@MainActor
private final class Probe: NSObject {
  private let byteCount: Int
  private let delegate = FragmentQueueDelegate()
  private let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
    styleMask: [.titled], backing: .buffered, defer: false)
  private let editor = NSTextView(usingTextLayoutManager: true)
  private var timer: Timer?
  private var ticks = 0
  private var finalResult: [String: Any]?
  private var exactTextAtSetup = false
  private var textDigest = ""
  private let began = ContinuousClock.now

  init(byteCount: Int) {
    self.byteCount = byteCount
    super.init()
  }

  func run() throws {
    guard let layout = editor.textLayoutManager,
      let storage = editor.textStorage,
      let container = editor.textContainer,
      let content = layout.textContentManager as? NSTextContentStorage
    else { throw Failure.textSystemUnavailable }

    let unit = "خط📝"
    let header = "123456789012345\n"
    let text = header + String(repeating: unit, count: (byteCount - 16) / 8)
    guard text.utf8.count == byteCount else { throw Failure.fixtureSize }

    let frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 900, height: 500)
    let scroll = NSScrollView(frame: frame)
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = false
    editor.frame = frame
    editor.isRichText = false
    editor.isEditable = true
    editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
    editor.textContainerInset = NSSize(width: 16, height: 16)
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    editor.autoresizingMask = [.width]
    container.widthTracksTextView = true
    container.containerSize = NSSize(
      width: 868, height: CGFloat.greatestFiniteMagnitude)
    layout.delegate = delegate
    scroll.documentView = editor
    window.contentView = scroll
    editor.string = text
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.contentView?.layoutSubtreeIfNeeded()
    window.displayIfNeeded()

    guard storage.string == text else { throw Failure.textChanged }
    exactTextAtSetup = true
    let digest = SHA256.hash(data: Data(storage.string.utf8)).map {
      String(format: "%02x", $0)
    }.joined()
    textDigest = digest

    timer = Timer(
      timeInterval: 0.2, target: self, selector: #selector(tick(_:)), userInfo: nil, repeats: true)
    if let timer { RunLoop.main.add(timer, forMode: .common) }
    let deadline = Date(timeIntervalSinceNow: 60.5)
    while finalResult == nil && Date() < deadline {
      _ = RunLoop.main.run(mode: .common, before: Date(timeIntervalSinceNow: 0.2))
    }
    timer?.invalidate()
    timer = nil
    let result = finalResult ?? observation(layout: layout, content: content, storage: storage)
    let encoded = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: encoded, as: UTF8.self))
    if result["completeCoverage"] as? Bool != true { exit(2) }
  }

  @objc private func tick(_ scheduledTimer: Timer) {
    guard let layout = editor.textLayoutManager,
      let content = layout.textContentManager as? NSTextContentStorage,
      let storage = editor.textStorage
    else {
      timer?.invalidate()
      timer = nil
      finalResult = ["failure": "textSystemUnavailable"]
      return
    }
    observe(layout: layout, content: content, storage: storage)
  }

  private func observe(
    layout: NSTextLayoutManager, content: NSTextContentStorage, storage: NSTextStorage
  ) {
    ticks += 1
    let result = observation(layout: layout, content: content, storage: storage)
    if ticks.isMultiple(of: 5) {
      let compact: [String: Any] = [
        "tick": ticks,
        "elapsedSeconds": result["elapsedSeconds"] ?? 0,
        "queueOperations": result["queueOperations"] ?? -1,
        "fragmentStates": result["fragmentStates"] ?? [],
        "lineCount": result["lineCount"] ?? 0,
        "coveredUTF16": result["coveredUTF16"] ?? 0,
        "completeCoverage": result["completeCoverage"] ?? false,
      ]
      if let data = try? JSONSerialization.data(withJSONObject: compact, options: [.sortedKeys]) {
        FileHandle.standardError.write(data + Data([0x0A]))
      }
    }
    if result["completeCoverage"] as? Bool == true {
      finalResult = result
      timer?.invalidate()
      timer = nil
    } else if ticks >= 300 {
      finalResult = result
      timer?.invalidate()
      timer = nil
    }
  }

  private func observation(
    layout: NSTextLayoutManager, content: NSTextContentStorage, storage: NSTextStorage
  ) -> [String: Any] {
    var fragments: [NSTextLayoutFragment] = []
    _ = layout.enumerateTextLayoutFragments(from: nil, options: []) { fragment in
      fragments.append(fragment)
      return true
    }

    var lineCount = 0
    var coveredUTF16 = 0
    var contiguous = true
    for fragment in fragments where fragment.state == .layoutAvailable {
      guard let element = fragment.textElement, let elementRange = element.elementRange else {
        contiguous = false
        continue
      }
      let elementStart = content.offset(
        from: content.documentRange.location, to: elementRange.location)
      for line in fragment.textLineFragments {
        let lineStart = elementStart + line.characterRange.location
        if lineStart != coveredUTF16 { contiguous = false }
        coveredUTF16 = lineStart + line.characterRange.length
        lineCount += 1
      }
    }
    let elapsed = began.duration(to: .now).components
    let elapsedSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    return [
      "requestedUTF8Bytes": byteCount,
      "actualUTF8Bytes": storage.string.utf8.count,
      "sourceUTF16": storage.length,
      "textSHA256": textDigest,
      "exactTextAtSetup": exactTextAtSetup,
      "queueOperations": delegate.queue.operationCount,
      "fragmentCount": fragments.count,
      "fragmentStates": fragments.map { $0.state.rawValue },
      "lineCount": lineCount,
      "coveredUTF16": coveredUTF16,
      "completeCoverage": contiguous && coveredUTF16 == storage.length
        && !fragments.isEmpty && fragments.allSatisfy({ $0.state == .layoutAvailable }),
      "elapsedSeconds": elapsedSeconds,
      "ticks": ticks,
    ]
  }

  private enum Failure: Error {
    case fixtureSize
    case textSystemUnavailable
    case textChanged
  }
}
