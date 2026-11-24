import AppKit
import Foundation

@MainActor
func run() throws {
  func mark(_ name: String, _ start: UInt64) {
    let ns = DispatchTime.now().uptimeNanoseconds - start
    print("\(name)=\(Double(ns) / 1_000_000_000)")
  }
  var start = DispatchTime.now().uptimeNanoseconds
  let pattern = "خط📝"
  let targetBytes = 10_485_760
  let text = String(repeating: pattern, count: max(1, targetBytes / pattern.utf8.count))
  mark("generate", start)
  start = DispatchTime.now().uptimeNanoseconds
  let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 868, height: 30))
  field.isEditable = true
  field.cell?.isScrollable = ProcessInfo.processInfo.environment["FIELD_SCROLL"] == "1"
  field.isSelectable = true
  field.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
  field.usesSingleLineMode = true
  field.lineBreakMode = ProcessInfo.processInfo.environment["FIELD_MODE"] == "tail" ? .byTruncatingTail : .byClipping
  mark("configure-field", start)
  start = DispatchTime.now().uptimeNanoseconds
  field.stringValue = text
  mark("assign-string", start)
  start = DispatchTime.now().uptimeNanoseconds
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 200), styleMask: [.borderless], backing: .buffered, defer: true)
  window.contentView?.addSubview(field)
  window.contentView?.layoutSubtreeIfNeeded()
  mark("attach-layout", start)
  if ProcessInfo.processInfo.environment["FIELD_EDIT"] == "1" {
    start = DispatchTime.now().uptimeNanoseconds
    field.selectText(nil)
    mark("select-text", start)
    if let editor = window.firstResponder as? NSTextView {
      start = DispatchTime.now().uptimeNanoseconds
      let value = editor.string
      mark("read-field-editor", start)
      print("fieldEditorTextMatches=\(value == text) editorUTF16=\(value.utf16.count)")
      return
    }
    print("fieldEditorUnavailable")
    return
  }
  start = DispatchTime.now().uptimeNanoseconds
  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 200, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  field.draw(field.bounds)
  NSGraphicsContext.restoreGraphicsState()
  mark("draw", start)
  print("bytes=\(text.utf8.count) utf16=\(text.utf16.count) fieldValueEqual=\(field.stringValue == text)")
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
try await MainActor.run { try run() }
