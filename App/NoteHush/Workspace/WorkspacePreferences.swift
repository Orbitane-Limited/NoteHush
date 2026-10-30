import AppKit
import NoteHushCore

extension WorkspaceWindowController {
  func zoom(increasing: Bool) {
    guard canNavigate else { return }
    applyPreferences(preferences.zoomed(increasing: increasing))
  }

  func resetZoom() {
    guard canNavigate else { return }
    var next = preferences
    next.zoomPercent = 100
    applyPreferences(next)
  }

  func toggleWordWrap() {
    guard canNavigate else { return }
    var next = preferences
    next.wordWrap.toggle()
    applyPreferences(next)
  }

  func showPageSetup() {
    guard canNavigate, let window else { return }
    printer.showPageSetup(on: window)
  }

  func printDocument(selectionOnly: Bool) {
    guard canNavigate, let tab = selectedTab, let window,
      let text = textForPrinting(selectionOnly: selectionOnly)
    else { return }
    printer.printText(text, font: preferences.font(zoomed: false), title: tab.title, on: window)
  }

  func textForPrinting(selectionOnly: Bool) -> String? {
    guard let tab = selectedTab else { return nil }
    if selectionOnly {
      let range = tab.textSelection
      guard range.length > 0 else { return nil }
      return (tab.text as NSString).substring(with: range)
    } else {
      return tab.text
    }
  }
}
