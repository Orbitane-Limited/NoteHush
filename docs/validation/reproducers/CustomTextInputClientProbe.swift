import AppKit
import Foundation

@MainActor
final class ProbeInputView: NSView, @preconcurrency NSTextInputClient {
  let storage = NSMutableAttributedString(string: "")
  private(set) var selection = NSRange(location: 0, length: 0)
  private var composition: NSRange?

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    if inputContext?.handleEvent(event) != true {
      interpretKeyEvents([event])
    }
  }

  func insertText(_ string: Any, replacementRange: NSRange) {
    let value = Self.attributed(string)
    let range =
      Self.validRange(replacementRange, length: storage.length) ?? composition
      ?? Self.validRange(selection, length: storage.length)
      ?? NSRange(location: storage.length, length: 0)
    storage.replaceCharacters(in: range, with: value)
    composition = nil
    selection = NSRange(location: range.location + value.length, length: 0)
  }

  func setMarkedText(
    _ string: Any, selectedRange relativeSelection: NSRange, replacementRange: NSRange
  ) {
    let value = Self.attributed(string)
    let range =
      Self.validRange(replacementRange, length: storage.length) ?? composition
      ?? Self.validRange(selection, length: storage.length)
      ?? NSRange(location: storage.length, length: 0)
    storage.replaceCharacters(in: range, with: value)
    composition = NSRange(location: range.location, length: value.length)
    let localSelection =
      Self.validRange(relativeSelection, length: value.length)
      ?? NSRange(location: value.length, length: 0)
    selection = NSRange(
      location: range.location + localSelection.location, length: localSelection.length)
  }

  func unmarkText() { composition = nil }
  func selectedRange() -> NSRange { selection }
  func markedRange() -> NSRange { composition ?? NSRange(location: NSNotFound, length: 0) }
  func hasMarkedText() -> Bool { composition != nil }

  func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?)
    -> NSAttributedString?
  {
    guard let safeRange = Self.validRange(range, length: storage.length) else { return nil }
    actualRange?.pointee = safeRange
    return storage.attributedSubstring(from: safeRange)
  }

  func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

  func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
    let safeRange = Self.validRange(range, length: storage.length) ?? selection
    actualRange?.pointee = safeRange
    return window?.convertToScreen(convert(bounds, to: nil)) ?? .zero
  }

  func characterIndex(for point: NSPoint) -> Int { NSNotFound }

  private static func attributed(_ value: Any) -> NSAttributedString {
    if let attributed = value as? NSAttributedString { return attributed }
    if let string = value as? String { return NSAttributedString(string: string) }
    if let string = value as? NSString { return NSAttributedString(string: string as String) }
    return NSAttributedString(string: "")
  }

  private static func validRange(_ range: NSRange, length: Int) -> NSRange? {
    guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
      range.location <= length, range.length <= length - range.location
    else { return nil }
    return range
  }
}

@MainActor
func verifyProbe() throws {
  let view = ProbeInputView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))
  view.insertText("A👩🏽‍💻B", replacementRange: NSRange(location: NSNotFound, length: 0))
  guard view.storage.string == "A👩🏽‍💻B",
    view.selectedRange().location == (view.storage.string as NSString).length
  else { throw NSError(domain: "CustomTextInputClientProbe", code: 1) }

  let emoji = NSRange(location: 1, length: 7)
  view.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0), replacementRange: emoji)
  guard view.hasMarkedText(), view.markedRange() == NSRange(location: 1, length: 2),
    view.selectedRange() == NSRange(location: 3, length: 0), view.storage.string == "AかなB"
  else { throw NSError(domain: "CustomTextInputClientProbe", code: 2) }

  view.insertText("仮名", replacementRange: NSRange(location: NSNotFound, length: 0))
  guard !view.hasMarkedText(), view.storage.string == "A仮名B",
    view.selectedRange() == NSRange(location: 3, length: 0)
  else { throw NSError(domain: "CustomTextInputClientProbe", code: 3) }
}

try await MainActor.run { try verifyProbe() }
print("Generated NSTextInputClient range/composition probe passed")
