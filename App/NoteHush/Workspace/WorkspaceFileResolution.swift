import AppKit
import NoteHushCore

@MainActor
extension WorkspaceWindowController {
  func saveExistingFile(_ tab: EditorTab) async {
    guard let file = tab.file, canEditFiles else { return }
    do {
      let located = try await fileService.locate(file, grantedURL: tab.grantedURL)
      guard canEditFiles else { return }
      tab.relocate(using: located.binding, grantedURL: located.scopedURL)
      didSaveFile()
      await saveResolvingConflict(
        tab, to: located.scopedURL, encoding: file.encoding, saveAs: false)
    } catch {
      guard canEditFiles else { return }
      await resolveUnavailableFile(tab)
    }
  }

  func saveResolvingConflict(
    _ tab: EditorTab, to url: URL, encoding: TextFileEncoding, saveAs: Bool
  ) async {
    do {
      try await writeFile(tab, to: url, encoding: encoding, saveAs: saveAs)
    } catch TextFileError.changedOnDisk {
      guard canEditFiles else { return }
      await resolveConflict(tab, at: url, encoding: encoding)
    } catch {
      guard canEditFiles else { return }
      showFileMessage(String(localized: "Save could not be confirmed. ") + fileErrorMessage(error))
    }
  }

  private func resolveUnavailableFile(_ tab: EditorTab) async {
    let alert = NSAlert()
    alert.messageText = String(localized: "File is unavailable")
    alert.informativeText = String(
      localized:
        "Your draft is safe. The file may have moved, been deleted, or lost access. Relink it or save your draft to another location."
    )
    for title in [
      String(localized: "Cancel"), String(localized: "Relink…"),
      String(localized: "Save As…"),
    ] {
      alert.addButton(withTitle: title)
    }
    let response = await presentResolutionAlert(alert)
    guard canEditFiles else { return }
    switch response {
    case .alertSecondButtonReturn: await relinkFile(tab)
    case .alertThirdButtonReturn: await saveCopy(tab)
    default: break
    }
  }

  private func resolveConflict(_ tab: EditorTab, at url: URL, encoding: TextFileEncoding) async {
    let external: OpenedTextFile
    do {
      external = try await fileService.open(url)
    } catch {
      // Never offer a blind overwrite of unreadable, missing or oversized data.
      guard canEditFiles else { return }
      await resolveUnavailableFile(tab)
      return
    }
    guard canEditFiles else { return }
    let alert = NSAlert()
    alert.messageText = String(localized: "File changed outside NoteHush")
    alert.informativeText = String(
      localized:
        "The disk version is shown below. Save As keeps both versions. Reload replaces this tab with the disk version and can be undone. Overwrite saves your draft over the version shown."
    )
    for title in [
      String(localized: "Cancel"), String(localized: "Save As…"),
      String(localized: "Reload File"), String(localized: "Overwrite File"),
    ] {
      alert.addButton(withTitle: title)
    }
    let preview = NSTextView(frame: NSRect(x: 0, y: 0, width: 440, height: 180))
    preview.isEditable = false
    preview.isRichText = false
    preview.isVerticallyResizable = true
    preview.autoresizingMask = [.width]
    preview.textContainer?.widthTracksTextView = true
    preview.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    preview.setAccessibilityLabel(String(localized: "Current disk version"))
    preview.setAccessibilityIdentifier("conflict-preview")
    // Keep sheet layout bounded even for the largest supported file.
    let prefix = external.text.utf8.prefix(64 * 1024)
    // Only the display preview may end with a repaired partial character; the
    // reviewed binding and reload buffer always retain the complete exact text.
    preview.string = String(decoding: prefix, as: UTF8.self)
    if prefix.count < external.text.utf8.count {
      preview.string += String(localized: "\n\n[Preview shortened. Reload uses the full version.]")
    }
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 180))
    scroll.hasVerticalScroller = true
    scroll.documentView = preview
    alert.accessoryView = scroll
    let response = await presentResolutionAlert(alert)
    guard canEditFiles else { return }
    switch response {
    case .alertSecondButtonReturn: await saveCopy(tab)
    case .alertThirdButtonReturn:
      tab.reload(external, grantedURL: url)
      didSaveFile()
      showFileMessage(
        String(localized: "Disk version loaded. Use Undo to restore your previous draft."))
    case NSApplication.ModalResponse(
      rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + 3):
      do {
        // Approve exactly the reviewed version, never disable the disk guard.
        try await writeFile(
          tab, to: url, encoding: encoding, saveAs: false,
          expected: external.binding)
      } catch {
        showFileMessage(
          String(
            localized:
              "The overwrite could not be confirmed. The file may have changed again. Your draft is intact; use Save to review it again."
          ))
      }
    default: break
    }
  }

  private func saveCopy(_ tab: EditorTab) async {
    guard let destination = await chooseSaveDestination(tab), canEditFiles else { return }
    // If this destination also conflicts, return to the editor with a warning.
    // Repeated choices must not retain a recursive chain of large disk previews.
    _ = await saveFile(tab, to: destination.0, encoding: destination.1, saveAs: true)
  }

  private func relinkFile(_ tab: EditorTab) async {
    guard let window, canEditFiles else { return }
    let panel = NSOpenPanel()
    panel.title = String(localized: "Relink Text File")
    panel.prompt = String(localized: "Relink")
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.preventsApplicationTerminationWhenModal = false
    filePanel = panel
    let response = await withCheckedContinuation { continuation in
      panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
    }
    filePanel = nil
    guard response == .OK, let url = panel.url, canEditFiles else { return }
    do {
      let opened = try await fileService.open(url)
      guard canEditFiles else { return }
      guard
        !tabs.contains(where: {
          $0.id != tab.id
            && ($0.file?.identity == opened.binding.identity
              || $0.file?.url == opened.binding.url)
        })
      else { throw TextFileError.alreadyOpen }
      tab.relocate(using: opened.binding, grantedURL: url)
      didSaveFile()
      showFileMessage(
        String(localized: "File relinked. Your draft is unchanged. Use Save to write it."))
    } catch {
      showFileMessage(String(localized: "File could not be relinked. ") + fileErrorMessage(error))
    }
  }
}
