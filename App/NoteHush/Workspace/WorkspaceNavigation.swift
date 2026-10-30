import AppKit

@MainActor
extension WorkspaceWindowController {
  var canNavigate: Bool {
    canEditFiles && window?.attachedSheet == nil && !printer.isPresenting && selectedTab != nil
  }

  func performFindAction(_ sender: Any?) {
    guard canNavigate, let tab = selectedTab else { return }
    tab.editor.performTextFinderAction(sender)
  }

  func validateFindAction(_ item: NSMenuItem) -> Bool {
    guard canNavigate, let tab = selectedTab else { return false }
    if item.tag == NSTextFinder.Action.setSearchString.rawValue {
      return tab.textSelection.length > 0
    }
    // NSTextView's responder validation depends on keyboard focus. The native
    // Find field may own focus while commands still address this document.
    return true
  }

  @objc func goToLine(_ sender: Any?) {
    guard canNavigate, navigationTask == nil, let tab = selectedTab else { return }
    let line = tab.metrics?.position(atUTF16Offset: tab.textSelection.location).line ?? 1
    let sheet = GoToLineSheet(line: line, lineCount: tab.metrics?.lineCount)
    navigationSheet = sheet
    navigationTask = Task { [weak self] in
      guard let self else { return }
      defer {
        navigationSheet = nil
        navigationTask = nil
      }
      let response = await presentResolutionAlert(sheet.alert, initialResponder: sheet.field)
      guard response == .alertFirstButtonReturn, canEditFiles, selectedTab?.id == tab.id,
        let line = sheet.selectedLine, let offset = tab.metrics?.utf16Offset(forLine: line)
      else { return }
      tab.selectText(NSRange(location: offset, length: 0), reveal: true)
      window?.makeFirstResponder(tab.editor)
    }
  }
}
