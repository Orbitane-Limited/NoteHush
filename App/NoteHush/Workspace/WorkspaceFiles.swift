import AppKit
import NoteHushCore

@MainActor
extension WorkspaceWindowController {
  @objc func openDocument(_ sender: Any?) {
    guard canEditFiles, filePanel == nil, resolutionAlert == nil else { return }
    let panel = NSOpenPanel()
    panel.preventsApplicationTerminationWhenModal = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.title = String(localized: "Open Text Files")
    guard let window else { return }
    filePanel = panel
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }
      filePanel = nil
      if response == .OK { beginOpening(panel.urls) }
    }
  }

  func beginOpening(_ urls: [URL]) {
    pendingFileURLs.append(contentsOf: urls)
    guard openingTask == nil else { return }
    openingTask = Task { [weak self] in
      guard let self else { return }
      defer {
        openingTask = nil
        if !pendingFileURLs.isEmpty, canEditFiles { beginOpening([]) }
      }
      while !pendingFileURLs.isEmpty, !Task.isCancelled {
        let batch = pendingFileURLs
        pendingFileURLs.removeAll()
        _ = await openFiles(batch)
      }
    }
  }

  @discardableResult
  func openFiles(_ urls: [URL]) async -> Bool {
    await waitUntilLoaded()
    guard canEditFiles, !Task.isCancelled else { return false }
    var errors = 0
    var lastError: Error?
    var largeFile = false
    var missingBookmark = false
    for url in urls {
      guard !Task.isCancelled, canEditFiles else { return false }
      showFileMessage(String(localized: "Opening text files…"), opening: true)
      do {
        let opened = try await fileService.open(url)
        guard !Task.isCancelled, canEditFiles else { return false }
        installFile(opened, grantedURL: url)
        largeFile = largeFile || opened.byteCount > TextDocumentCodec.largeFileBytes
        missingBookmark = missingBookmark || opened.binding.bookmark == nil
      } catch is CancellationError {
        return false
      } catch {
        errors += 1
        lastError = error
      }
    }
    if let lastError {
      showFileMessage(
        String(localized: "\(errors) file(s) could not be opened. ") + fileErrorMessage(lastError))
    } else {
      showFileMessage(
        missingBookmark
          ? String(
            localized:
              "Opened. Access could not be remembered; you may need to relink after restarting.")
          : (largeFile
            ? String(localized: "Large file opened. Editing and layout may take longer.") : nil))
    }
    return errors == 0
  }

  @objc func saveDocument(_ sender: Any?) { beginSaving(saveAs: false) }
  @objc func saveDocumentAs(_ sender: Any?) { beginSaving(saveAs: true) }

  private func beginSaving(saveAs: Bool) {
    guard canEditFiles, savingTask == nil, filePanel == nil, resolutionAlert == nil,
      let tab = selectedTab
    else { return }
    savingTask = Task { [weak self] in
      guard let self else { return }
      defer { savingTask = nil }
      if !saveAs, tab.file != nil {
        await saveExistingFile(tab)
      } else {
        guard let destination = await chooseSaveDestination(tab), canEditFiles else { return }
        await saveResolvingConflict(
          tab, to: destination.0, encoding: destination.1, saveAs: true)
      }
    }
  }

  @discardableResult
  func saveFile(_ tab: EditorTab, to url: URL, encoding: TextFileEncoding, saveAs: Bool) async
    -> Bool
  {
    guard canEditFiles else { return false }
    do {
      try await writeFile(tab, to: url, encoding: encoding, saveAs: saveAs)
      return true
    } catch {
      showFileMessage(String(localized: "Save could not be confirmed. ") + fileErrorMessage(error))
      return false
    }
  }

  func writeFile(
    _ tab: EditorTab, to url: URL, encoding: TextFileEncoding, saveAs: Bool,
    expected: FileBinding? = nil
  ) async throws {
    guard canEditFiles else { throw CancellationError() }
    let text = tab.editor.string
    let protectedFiles = tabs.filter { $0.id != tab.id }.compactMap(\.file)
    let binding = try await fileService.save(
      text, encoding: encoding, to: url, expected: expected ?? tab.file,
      saveAs: saveAs, protectedFiles: protectedFiles)
    tab.bind(binding, grantedURL: url)
    didSaveFile()
    showFileMessage(
      binding.bookmark == nil
        ? String(
          localized:
            "Saved. Access could not be remembered; you may need to relink this file after restarting."
        )
        : nil)
  }

  func chooseSaveDestination(_ tab: EditorTab) async -> (URL, TextFileEncoding)? {
    guard let window else { return nil }
    let panel = NSSavePanel()
    panel.preventsApplicationTerminationWhenModal = false
    panel.title = String(localized: "Save Text File")
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.nameFieldStringValue = tab.file == nil ? "Untitled.txt" : tab.title
    if let file = tab.file { panel.directoryURL = file.url.deletingLastPathComponent() }
    let encoding = NSPopUpButton()
    encoding.addItems(withTitles: TextFileEncoding.allCases.map(\.displayName))
    encoding.selectItem(
      at: TextFileEncoding.allCases.firstIndex(of: tab.file?.encoding ?? .utf8) ?? 0)
    encoding.setAccessibilityLabel(String(localized: "Text encoding"))
    encoding.setAccessibilityIdentifier("save-encoding")
    let accessory = NSStackView(views: [
      NSTextField(labelWithString: String(localized: "Text encoding:")), encoding,
    ])
    accessory.spacing = 8
    panel.accessoryView = accessory
    filePanel = panel
    let response = await withCheckedContinuation { continuation in
      panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
    }
    filePanel = nil
    guard response == .OK, let url = panel.url else { return nil }
    return (url, TextFileEncoding.allCases[max(0, encoding.indexOfSelectedItem)])
  }

  func fileErrorMessage(_ error: Error) -> String {
    switch error as? TextFileError {
    case .invalidEncoding:
      String(
        localized: "Use UTF-8 or UTF-16 with a byte-order mark. Invalid bytes were not replaced.")
    case .binaryContent, .notRegularFile:
      String(
        localized: "Choose a plain-text file. Binary content and special files are not supported.")
    case .tooLarge:
      String(localized: "The file exceeds the 100 MiB limit.")
    case .changedOnDisk:
      String(
        localized:
          "The original file changed or is unavailable. Your draft is intact; use Save As to choose another location."
      )
    case .alreadyOpen:
      String(localized: "That destination is already open in another tab. Choose another location.")
    default:
      String(
        localized: "Check access to the location and try again. Your existing drafts are unchanged."
      )
    }
  }
}
