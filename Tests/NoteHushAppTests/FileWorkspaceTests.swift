import AppKit
import NoteHushCore
import XCTest

@MainActor
final class FileWorkspaceTests: XCTestCase {
  func testCancelledOpenCannotInstallALateResult() async throws {
    _ = NSApplication.shared
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "late.txt")
    try Data("late result".utf8).write(to: file)
    let service = DelayedFileRead()
    let controller = WorkspaceWindowController(
      store: RecoveryStore(directory: root.appending(path: "Recovery")), fileService: service)
    await controller.waitUntilLoaded()
    controller.beginOpening([file])
    await service.waitForRead()
    controller.cancelOpening(nil)
    await service.releaseRead()
    await controller.openingTask?.value
    XCTAssertEqual(controller.tabs.count, 1)
    XCTAssertEqual(controller.selectedTab?.editor.string, "")
    await controller.prepareToQuit()
    controller.close()
  }

  func testMultipleOpenDeduplicationAndDirtyFileRecoveryNeverReloadSource() async throws {
    _ = NSApplication.shared
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appending(path: "اردو.config")
    let second = root.appending(path: "second")
    let source = "اردو 👩🏽‍💻\r\nOriginal\n"
    try TextDocumentCodec.encode(source, as: .utf16BE).write(to: first)
    try Data("second".utf8).write(to: second)
    let recovery = root.appending(path: "Recovery")
    let controller = WorkspaceWindowController(directory: recovery)
    await controller.waitUntilLoaded()
    let opened = await controller.openFiles([first, second, first])
    XCTAssertTrue(opened)
    XCTAssertEqual(controller.tabs.count, 3)
    let tab = try XCTUnwrap(controller.selectedTab)
    XCTAssertEqual(tab.file?.encoding, .utf16BE)
    XCTAssertEqual(Data(tab.editor.string.utf8), Data(source.utf8))
    tab.editor.insertText("Draft", replacementRange: NSRange(location: 0, length: 0))
    await tab.waitForDirtyState()
    XCTAssertTrue(tab.isDirty)
    let edited = tab.editor.string
    await controller.prepareToQuit()
    controller.close()
    XCTAssertEqual(try TextDocumentCodec.decode(Data(contentsOf: first)).text, source)
    try Data("External replacement".utf8).write(to: first, options: .atomic)
    let restored = WorkspaceWindowController(directory: recovery)
    await restored.waitUntilLoaded()
    let recovered = try XCTUnwrap(restored.selectedTab)
    XCTAssertEqual(recovered.editor.string, edited)
    XCTAssertNil(recovered.grantedURL, "A stored path must not act as sandbox authority")
    _ = await restored.openFiles([first])
    XCTAssertEqual(restored.tabs.count, 3)
    XCTAssertEqual(restored.selectedTab?.editor.string, edited)
    let saved = await restored.saveFile(recovered, to: first, encoding: .utf16BE, saveAs: false)
    XCTAssertFalse(saved)
    XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "External replacement")
    await restored.prepareToQuit()
    restored.close()
  }

  func testFailedSaveKeepsDirtyTextAndOriginalBinding() async throws {
    _ = NSApplication.shared
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "original.txt")
    try Data("original".utf8).write(to: file)
    let controller = WorkspaceWindowController(
      store: RecoveryStore(directory: root.appending(path: "Recovery")),
      fileService: TextFileService(publisher: FailedPublication()))
    _ = await controller.openFiles([file])
    let tab = try XCTUnwrap(controller.selectedTab)
    let originalBinding = tab.file
    tab.editor.insertText(" changed", replacementRange: NSRange(location: 8, length: 0))
    let saved = await controller.saveFile(tab, to: file, encoding: .utf8, saveAs: false)
    XCTAssertFalse(saved)
    await tab.waitForDirtyState()
    XCTAssertTrue(tab.isDirty)
    XCTAssertEqual(tab.editor.string, "original changed")
    XCTAssertEqual(tab.file, originalBinding)
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "original")
    await controller.prepareToQuit()
    controller.close()
  }

  func testTypingDuringSaveRemainsDirtyAndUndoToSavedBytesClearsDirtyState() async throws {
    _ = NSApplication.shared
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let service = GatedFileAccess()
    let controller = WorkspaceWindowController(
      store: RecoveryStore(directory: root.appending(path: "Recovery")), fileService: service)
    await controller.waitUntilLoaded()
    let tab = try XCTUnwrap(controller.selectedTab)
    tab.editor.insertText("saved", replacementRange: NSRange(location: 0, length: 0))
    let url = root.appending(path: "race.txt")
    let saving = Task { await controller.saveFile(tab, to: url, encoding: .utf8, saveAs: true) }
    await service.waitForSave()
    let history = try XCTUnwrap(tab.undoManager(for: tab.editor))
    tab.editor.breakUndoCoalescing()
    history.beginUndoGrouping()
    tab.editor.insertText(" later", replacementRange: NSRange(location: 5, length: 0))
    history.endUndoGrouping()
    await service.releaseSave()
    let saved = await saving.value
    XCTAssertTrue(saved)
    await tab.waitForDirtyState()
    XCTAssertTrue(tab.isDirty)
    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "saved")
    XCTAssertEqual(tab.editor.string, "saved later")
    history.undo()
    await tab.waitForDirtyState()
    XCTAssertEqual(tab.editor.string, "saved")
    XCTAssertFalse(tab.isDirty)
    await controller.prepareToQuit()
    controller.close()
  }

  private func makeRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "NoteHushFileWorkspaceTests-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
}

private struct FailedPublication: TextFilePublishing {
  func publish(_ data: Data, to url: URL) throws { throw TextFileError.unavailable }
}

private actor GatedFileAccess: TextFileAccess {
  private let real = TextFileService()
  private var gate: CheckedContinuation<Void, Never>?
  private var observer: CheckedContinuation<Void, Never>?
  func open(_ url: URL) async throws -> OpenedTextFile { try await real.open(url) }
  func save(
    _ text: String, encoding: TextFileEncoding, to url: URL, expected: FileBinding?, saveAs: Bool,
    protectedFiles: [FileBinding]
  ) async throws -> FileBinding {
    await withCheckedContinuation {
      gate = $0
      observer?.resume()
      observer = nil
    }
    return try await real.save(
      text, encoding: encoding, to: url, expected: expected, saveAs: saveAs,
      protectedFiles: protectedFiles)
  }
  func waitForSave() async {
    if gate != nil { return }
    await withCheckedContinuation { observer = $0 }
  }
  func releaseSave() {
    gate?.resume()
    gate = nil
  }
}

private actor DelayedFileRead: TextFileAccess {
  private let real = TextFileService()
  private var gate: CheckedContinuation<Void, Never>?
  private var observer: CheckedContinuation<Void, Never>?
  func open(_ url: URL) async throws -> OpenedTextFile {
    let result = try await real.open(url)
    await withCheckedContinuation {
      gate = $0
      observer?.resume()
      observer = nil
    }
    return result
  }
  func waitForRead() async {
    if gate != nil { return }
    await withCheckedContinuation { observer = $0 }
  }
  func releaseRead() {
    gate?.resume()
    gate = nil
  }
  func save(
    _ text: String, encoding: TextFileEncoding, to url: URL, expected: FileBinding?, saveAs: Bool,
    protectedFiles: [FileBinding]
  ) async throws -> FileBinding {
    try await real.save(
      text, encoding: encoding, to: url, expected: expected, saveAs: saveAs,
      protectedFiles: protectedFiles)
  }
}
