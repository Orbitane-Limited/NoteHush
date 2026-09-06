import AppKit
import NoteHushCore
import XCTest

@MainActor
final class FileResolutionTests: XCTestCase {
  func testReloadCanUndoToDraftAndNeverWritesDisk() async throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appending(path: "NoteHushReload-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "original.txt")
    try Data("old".utf8).write(to: file)
    let service = TextFileService()
    let old = try await service.open(file)
    let tab = EditorTab(snapshot: TabSnapshot(text: "draft 👩🏽‍💻", file: old.binding))
    try Data("external\r\nاردو".utf8).write(to: file, options: .atomic)
    let external = try await service.open(file)
    tab.reload(external, grantedURL: file)
    await tab.waitForDirtyState()
    XCTAssertEqual(tab.editor.string, external.text)
    XCTAssertFalse(tab.isDirty)
    tab.undoManager(for: tab.editor)?.undo()
    await tab.waitForDirtyState()
    XCTAssertEqual(tab.editor.string, "draft 👩🏽‍💻")
    XCTAssertTrue(tab.isDirty)
    XCTAssertEqual(try Data(contentsOf: file), Data(external.text.utf8))
  }

  func testRelinkKeepsDraftAndOriginalSaveBaseline() async throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appending(path: "NoteHushRelink-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appending(path: "old.txt")
    let second = root.appending(path: "new.txt")
    try Data("old".utf8).write(to: first)
    try Data("external".utf8).write(to: second)
    let service = TextFileService()
    let old = try await service.open(first)
    let candidate = try await service.open(second)
    let tab = EditorTab(snapshot: TabSnapshot(text: "draft", file: old.binding))
    tab.relocate(using: candidate.binding, grantedURL: second)
    XCTAssertEqual(tab.title, "new.txt")
    XCTAssertEqual(tab.editor.string, "draft")
    XCTAssertEqual(tab.file?.identity, old.binding.identity)
    XCTAssertEqual(tab.file?.fileDigest, old.binding.fileDigest)
    XCTAssertEqual(tab.file?.url, candidate.binding.url)
    XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "external")
  }
}
