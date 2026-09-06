import AppKit

@MainActor
final class GoToLineSheet: NSObject, NSTextFieldDelegate {
  let alert = NSAlert()
  let field = NSTextField(string: "1")
  private let hint = NSTextField(wrappingLabelWithString: "")
  private var lineCount: Int?

  init(line: Int, lineCount: Int?) {
    super.init()
    alert.messageText = String(localized: "Go to Line")
    alert.informativeText = String(localized: "Enter a line number.")
    alert.addButton(withTitle: String(localized: "Go"))
    alert.addButton(withTitle: String(localized: "Cancel"))
    field.stringValue = String(line)
    field.setAccessibilityLabel(String(localized: "Line number"))
    field.setAccessibilityIdentifier("go-to-line-number")
    field.delegate = self
    hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    hint.setAccessibilityIdentifier("go-to-line-hint")
    let stack = NSStackView(views: [field, hint])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.frame = NSRect(x: 0, y: 0, width: 240, height: 56)
    field.widthAnchor.constraint(equalToConstant: 240).isActive = true
    hint.widthAnchor.constraint(equalToConstant: 240).isActive = true
    alert.accessoryView = stack
    update(lineCount: lineCount)
  }

  var selectedLine: Int? {
    guard let number = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
      let lineCount, (1...lineCount).contains(number)
    else { return nil }
    return number
  }

  func update(lineCount: Int?) {
    self.lineCount = lineCount
    validate()
  }

  func controlTextDidChange(_ notification: Notification) { validate() }

  private func validate() {
    alert.buttons[0].isEnabled = selectedLine != nil
    if let lineCount {
      hint.stringValue = String(localized: "Enter a number from 1 to \(lineCount).")
    } else {
      hint.stringValue = String(localized: "Updating line numbers…")
    }
  }
}
