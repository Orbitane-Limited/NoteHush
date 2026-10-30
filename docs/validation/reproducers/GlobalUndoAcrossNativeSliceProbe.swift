@preconcurrency import AppKit
import Foundation

@MainActor
final class SliceEditor: NSTextView {
  var nativeUndoManager = UndoManager()
  var globalUndoManager = UndoManager()

  func configureUndoManagers(sharesUndoManager: Bool) {
    let history = UndoManager()
    globalUndoManager = history
    nativeUndoManager = sharesUndoManager ? history : UndoManager()
  }

  override var undoManager: UndoManager? { nativeUndoManager }
  @objc func undo(_ sender: Any?) { globalUndoManager.undo() }
  @objc func redo(_ sender: Any?) { globalUndoManager.redo() }

  override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    if item.action == #selector(undo(_:)) { return globalUndoManager.canUndo }
    if item.action == #selector(redo(_:)) { return globalUndoManager.canRedo }
    return true
  }
}

@MainActor
final class SliceHost: NSView, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
  let editor: SliceEditor
  private let storage: NSTextStorage
  private let source: NSMutableAttributedString
  let history: UndoManager
  private var pending: (range: NSRange, old: String, replacement: String, selection: NSRange)?
  private var replacing = false
  private(set) var displayed = 0..<0
  private var globalSelection = NSRange(location: 0, length: 0)
  var text: String { source.string }

  init(text: String, sharesUndoManager: Bool = false) throws {
    source = NSMutableAttributedString(string: text)
    editor = SliceEditor(usingTextLayoutManager: true)
    editor.configureUndoManagers(sharesUndoManager: sharesUndoManager)
    guard let storage = editor.textStorage else {
      throw NSError(domain: "undo-probe", code: 10)
    }
    self.storage = storage
    history = editor.globalUndoManager
    super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    editor.allowsUndo = false
    editor.delegate = self
    storage.delegate = self
    addSubview(editor)
  }

  required init?(coder: NSCoder) { nil }
  func undoManager(for view: NSTextView) -> UndoManager? { view.undoManager }

  func show(_ range: Range<Int>, captureSelection: Bool = true) {
    let localSelection = editor.selectedRange()
    if captureSelection, localSelection.location != NSNotFound,
      localSelection.location >= 0,
      NSMaxRange(localSelection) <= displayed.count
    {
      globalSelection = NSRange(
        location: displayed.lowerBound + localSelection.location, length: localSelection.length)
    }
    let bounded = min(range.lowerBound, source.length)..<min(range.upperBound, source.length)
    replacing = true
    storage.setAttributedString(
      source.attributedSubstring(from: NSRange(location: bounded.lowerBound, length: bounded.count))
    )
    displayed = bounded
    editor.frame = NSRect(
      x: 0, y: CGFloat(bounded.lowerBound / 40) * 17, width: 600,
      height: max(400, CGFloat(bounded.count / 40) * 17))
    if globalSelection.location >= bounded.lowerBound,
      NSMaxRange(globalSelection) <= bounded.upperBound
    {
      editor.setSelectedRange(
        NSRange(
          location: globalSelection.location - bounded.lowerBound, length: globalSelection.length))
    }
    replacing = false
  }

  func globalSelectionForProbe() -> NSRange { globalSelection }

  func textView(
    _ textView: NSTextView, shouldChangeTextInRanges ranges: [NSValue],
    replacementStrings: [String]?
  ) -> Bool {
    guard ranges.count == 1, let replacementStrings, replacementStrings.count == 1 else {
      return false
    }
    let local = ranges[0].rangeValue
    let global = NSRange(location: displayed.lowerBound + local.location, length: local.length)
    let localSelection = editor.selectedRange()
    let selection = NSRange(
      location: displayed.lowerBound + localSelection.location, length: localSelection.length)
    pending = (
      global, (source.string as NSString).substring(with: global), replacementStrings[0], selection
    )
    return true
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    guard !replacing else { return }
    let local = editor.selectedRange()
    guard local.location != NSNotFound, local.location >= 0,
      NSMaxRange(local) <= displayed.count
    else { return }
    globalSelection = NSRange(location: displayed.lowerBound + local.location, length: local.length)
  }

  func textStorage(
    _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
    range: NSRange, changeInLength delta: Int
  ) {
    guard !replacing, editedMask.contains(.editedCharacters) else { return }
    let oldRange = displayed
    source.replaceCharacters(
      in: NSRange(location: oldRange.lowerBound, length: oldRange.count), with: textStorage)
    displayed = oldRange.lowerBound..<(oldRange.lowerBound + textStorage.length)
    let localSelection = editor.selectedRange()
    if localSelection.location != NSNotFound, localSelection.location >= 0,
      NSMaxRange(localSelection) <= displayed.count
    {
      globalSelection = NSRange(
        location: displayed.lowerBound + localSelection.location, length: localSelection.length)
    }
    guard let pending else { return }
    self.pending = nil
    history.registerUndo(withTarget: self) { target in
      target.apply(
        NSRange(location: pending.range.location, length: pending.replacement.utf16.count),
        replacement: pending.old, selection: pending.selection)
    }
  }

  private func apply(_ range: NSRange, replacement: String, selection: NSRange) {
    let current = (source.string as NSString).substring(with: range)
    let oppositeSelection = globalSelection
    source.replaceCharacters(in: range, with: replacement)
    history.registerUndo(withTarget: self) { target in
      target.apply(
        NSRange(location: range.location, length: replacement.utf16.count), replacement: current,
        selection: oppositeSelection)
    }
    let selectionLocation = min(max(0, selection.location), source.length)
    let selectionLength = min(max(0, selection.length), source.length - selectionLocation)
    globalSelection = NSRange(location: selectionLocation, length: selectionLength)
    let caret = globalSelection.location
    let lower = max(0, caret - 200)
    show(lower..<min(source.length, lower + 800), captureSelection: false)
  }
}

@main
@MainActor
enum Probe {
  static func main() throws {
    setbuf(stdout, nil)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let unit = "خط📝 paragraph "
    let initial = String(repeating: unit, count: 20_000)
    let baseline = Array(initial.utf16)
    let sharedHost = try SliceHost(text: initial, sharesUndoManager: true)
    let sharedScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    sharedScroll.documentView = sharedHost
    let sharedWindow = NSWindow(
      contentRect: sharedScroll.frame, styleMask: .borderless, backing: .buffered, defer: false)
    sharedWindow.contentView = sharedScroll
    let editGlobal = 150_000
    sharedHost.show(editGlobal..<editGlobal + 800)
    sharedHost.editor.setSelectedRange(NSRange(location: 40, length: 0))
    sharedHost.editor.insertText("Z", replacementRange: NSRange(location: NSNotFound, length: 0))
    sharedHost.show(0..<800)
    sharedHost.editor.undo(nil)
    let sharedUndoRestoredSource = Array(sharedHost.text.utf16) == baseline
    guard !sharedUndoRestoredSource else { throw NSError(domain: "undo-probe", code: 11) }
    print("sharedNativeAndGlobalUndo=failed exactSource=false")
    sharedWindow.close()

    let host = try SliceHost(text: initial)
    let undoItem = NSMenuItem(
      title: "Undo", action: #selector(SliceEditor.undo(_:)), keyEquivalent: "z")
    let redoItem = NSMenuItem(
      title: "Redo", action: #selector(SliceEditor.redo(_:)), keyEquivalent: "Z")
    guard !host.editor.validateUserInterfaceItem(undoItem),
      !host.editor.validateUserInterfaceItem(redoItem)
    else { throw NSError(domain: "undo-probe", code: 4) }
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    scroll.documentView = host
    let window = NSWindow(
      contentRect: scroll.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = scroll
    host.show(editGlobal..<editGlobal + 800)
    host.editor.setSelectedRange(NSRange(location: 40, length: 0))
    let changed = (initial as NSString).replacingCharacters(
      in: NSRange(location: editGlobal + 40, length: 0), with: "Z")
    host.editor.insertText("Z", replacementRange: NSRange(location: NSNotFound, length: 0))
    guard Array(host.text.utf16) == Array(changed.utf16), host.history.canUndo else {
      throw NSError(domain: "undo-probe", code: 1)
    }
    guard host.editor.validateUserInterfaceItem(undoItem),
      !host.editor.validateUserInterfaceItem(redoItem)
    else { throw NSError(domain: "undo-probe", code: 5) }
    host.show(0..<800)
    host.editor.undo(nil)
    let afterUndo = Array(host.text.utf16)
    guard afterUndo == baseline else {
      let diff = zip(afterUndo, baseline).enumerated().first { $0.element.0 != $0.element.1 }
      throw NSError(
        domain: "undo-probe", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "undo did not restore source, firstDiff=\(String(describing: diff))"
        ])
    }
    guard host.globalSelectionForProbe() == NSRange(location: editGlobal + 40, length: 0) else {
      throw NSError(domain: "undo-probe", code: 8)
    }
    guard !host.editor.validateUserInterfaceItem(undoItem),
      host.editor.validateUserInterfaceItem(redoItem)
    else { throw NSError(domain: "undo-probe", code: 6) }
    host.editor.redo(nil)
    guard Array(host.text.utf16) == Array(changed.utf16) else {
      throw NSError(domain: "undo-probe", code: 3)
    }
    guard host.globalSelectionForProbe() == NSRange(location: editGlobal + 41, length: 0) else {
      throw NSError(domain: "undo-probe", code: 9)
    }
    guard host.editor.validateUserInterfaceItem(undoItem),
      !host.editor.validateUserInterfaceItem(redoItem)
    else { throw NSError(domain: "undo-probe", code: 7) }
    print(
      "globalUndoAcrossRebind=passed utf16=\(baseline.count) globalEdit=\(editGlobal + 40) undo=true redo=true selectionExact=true"
    )
    window.close()
  }
}
