import AppKit
import XCTest

@MainActor
final class FileAccessTests: XCTestCase {
  private var app: XCUIApplication!
  private var root: URL!
  private var editor: XCUIElement { app.textViews["note-editor"].firstMatch }

  override func setUp() async throws {
    continueAfterFailure = false
    executionTimeAllowance = 60
    app = XCUIApplication()
    app.launchEnvironment["NOTEHUSH_TEST_WORKSPACE"] = UUID().uuidString
    root = FileManager.default.temporaryDirectory.appending(path: "NoteHushAccessTests-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    app.terminate()
    try FileManager.default.removeItem(at: root)
    app = nil
  }

  func testBookmarkFollowsMoveAcrossFoldersAfterRestartAndRefreshesAfterSave() throws {
    let source = try createSource()
    open(source)
    replaceDraft("persistent draft")
    quit()
    let folder = root.appending(path: "Another Folder", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let moved = folder.appending(path: "renamed.txt")
    try FileManager.default.moveItem(at: source, to: moved)
    launch()
    XCTAssertEqual(editor.value as? String, "persistent draft")
    app.typeKey("s", modifierFlags: .command)
    expectFile(moved, text: "persistent draft")
    XCTAssertFalse(app.sheets.firstMatch.exists, "Restored permission must not require a panel")
    quit()
    launch()
    replaceDraft("second save after replacement")
    app.typeKey("s", modifierFlags: .command)
    expectFile(moved, text: "second save after replacement")
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
  }

  func testConflictReloadAndUndoPreserveDraftWithoutWritingSource() throws {
    let source = try createSource()
    open(source)
    replaceDraft("my draft")
    try Data("external version".utf8).write(to: source, options: .atomic)
    showConflict()
    XCTAssertEqual(app.textViews["conflict-preview"].value as? String, "external version")
    let screenshot = XCTAttachment(screenshot: app.windows["NoteHush"].screenshot())
    screenshot.name = "External conflict preview"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.sheets.buttons["Reload File"].click()
    expectEditor("external version")
    app.typeKey("z", modifierFlags: .command)
    expectEditor("my draft")
    XCTAssertEqual(try Data(contentsOf: source), Data("external version".utf8))
    quit()
    launch()
    expectEditor("my draft")
  }

  func testOverwriteRejectsNewerDiskEditAndRequiresAnotherReview() throws {
    let source = try createSource()
    open(source)
    replaceDraft("my draft")
    try Data("reviewed".utf8).write(to: source, options: .atomic)
    showConflict()
    try Data("newer external edit".utf8).write(to: source, options: .atomic)
    app.sheets.buttons["Overwrite File"].click()
    let message = app.staticTexts["file-message"]
    let failed = XCTNSPredicateExpectation(
      predicate:
        NSPredicate(format: "value CONTAINS %@", "overwrite could not be confirmed"),
      object: message)
    wait(for: [failed], timeout: 5)
    XCTAssertEqual(try Data(contentsOf: source), Data("newer external edit".utf8))
    expectEditor("my draft")
    showConflict()
    XCTAssertEqual(app.textViews["conflict-preview"].value as? String, "newer external edit")
    app.sheets.buttons["Overwrite File"].click()
    expectFile(source, text: "my draft")
  }

  func testQuitWithConflictSheetKeepsBothVersionsWithoutConfirmation() throws {
    let source = try createSource()
    open(source)
    replaceDraft("quit draft")
    try Data("external".utf8).write(to: source, options: .atomic)
    showConflict()
    quit()
    XCTAssertEqual(try Data(contentsOf: source), Data("external".utf8))
    launch()
    expectEditor("quit draft")
  }

  func testDeletedFileRelinkThenSaveAsKeepsDraftAndOtherFile() throws {
    let source = try createSource()
    let candidate = root.appending(path: "candidate.txt")
    try Data("candidate text".utf8).write(to: candidate)
    open(source)
    replaceDraft("relinked draft")
    try FileManager.default.removeItem(at: source)
    app.typeKey("s", modifierFlags: .command)
    let relink = app.sheets.buttons["Relink…"]
    XCTAssertTrue(relink.waitForExistence(timeout: 5))
    relink.click()
    goTo(candidate)
    app.sheets.buttons["OKButton"].firstMatch.click()
    let relinked = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value CONTAINS %@", "File relinked"),
      object: app.staticTexts["file-message"])
    wait(for: [relinked], timeout: 5)
    expectEditor("relinked draft")
    XCTAssertEqual(try Data(contentsOf: candidate), Data("candidate text".utf8))
    showConflict()
    app.sheets.buttons["Save As…"].click()
    let name = app.sheets.textFields["saveAsNameTextField"].firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.click()
    app.typeKey("a", modifierFlags: .command)
    name.typeText("safe-copy.txt")
    app.sheets.buttons["OKButton"].firstMatch.click()
    expectFile(root.appending(path: "safe-copy.txt"), text: "relinked draft")
    XCTAssertEqual(try Data(contentsOf: candidate), Data("candidate text".utf8))
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
  }

  func testDeniedFileAccessKeepsDraftAndCanCancelResolution() throws {
    let source = try createSource()
    open(source)
    replaceDraft("denied draft")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
    }
    app.typeKey("s", modifierFlags: .command)
    XCTAssertTrue(app.sheets.buttons["Relink…"].waitForExistence(timeout: 5))
    app.sheets.buttons["Cancel"].click()
    expectEditor("denied draft")
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
    XCTAssertEqual(try Data(contentsOf: source), Data("original".utf8))
  }

  func testMountedVolumeSaveAndQuitKeepsUnsavedDraft() throws {
    let fixture = try volumeFixture(phase: "mounted")
    open(fixture.source)
    replaceDraft("volume draft")
    app.typeKey("s", modifierFlags: .command)
    expectFile(fixture.source, text: "volume draft")
    replaceDraft("offline draft")
    quit()
    XCTAssertEqual(try Data(contentsOf: fixture.source), Data("volume draft".utf8))
  }

  func testUnavailableVolumeRestoresDraftWithoutMounting() throws {
    let fixture = try volumeFixture(phase: "offline")
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
    launch()
    expectEditor("offline draft")
    app.typeKey("s", modifierFlags: .command)
    XCTAssertTrue(app.sheets.buttons["Relink…"].waitForExistence(timeout: 5))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
    quit()
    launch()
    expectEditor("offline draft")
  }

  private struct VolumeFixture: Decodable {
    let workspace: String
    let source: URL
    let phase: String
  }

  private func volumeFixture(phase: String) throws -> VolumeFixture {
    // The host harness mounts/unmounts between two test invocations. The runner
    // can read the generated manifest, but cannot manage disk images itself.
    let manifest = URL(filePath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "build/volume-fixture.json")
    guard FileManager.default.fileExists(atPath: manifest.path) else {
      throw XCTSkip("Run scripts/test_app.sh for the host-managed APFS volume scenarios")
    }
    let data = try Data(contentsOf: manifest)
    struct Manifest: Decodable {
      let workspace: String
      let source: String
      let phase: String
    }
    let stored = try JSONDecoder().decode(Manifest.self, from: data)
    XCTAssertNotNil(UUID(uuidString: stored.workspace))
    XCTAssertEqual(stored.phase, phase, "Run scripts/test_app.sh to prepare both volume phases")
    app.launchEnvironment["NOTEHUSH_TEST_WORKSPACE"] = stored.workspace
    return VolumeFixture(
      workspace: stored.workspace, source: URL(filePath: stored.source),
      phase: stored.phase)
  }

  private func createSource() throws -> URL {
    let source = root.appending(path: "source.txt")
    try Data("original".utf8).write(to: source)
    return source
  }

  private func launch() {
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
  }

  private func quit() {
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
  }

  private func open(_ url: URL) {
    launch()
    app.typeKey("o", modifierFlags: .command)
    goTo(url)
    app.sheets.buttons["OKButton"].firstMatch.click()
    XCTAssertTrue(
      app.radioButtons.matching(
        NSPredicate(format: "label == %@", "\(url.lastPathComponent), tab 2 of 2")
      )
      .firstMatch.waitForExistence(timeout: 10))
  }

  private func goTo(_ url: URL) {
    app.typeKey("g", modifierFlags: [.command, .shift])
    let field = app.textFields["PathTextField"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.click()
    app.typeKey("a", modifierFlags: .command)
    field.typeText(url.path)
    app.typeKey(.return, modifierFlags: [])
  }

  private func replaceDraft(_ text: String) {
    editor.click()
    app.typeKey("a", modifierFlags: .command)
    editor.typeText(text)
    expectEditor(text)
  }

  private func showConflict() {
    app.typeKey("s", modifierFlags: .command)
    XCTAssertTrue(app.sheets.buttons["Overwrite File"].waitForExistence(timeout: 5))
  }

  private func expectEditor(_ text: String) {
    let loaded = XCTNSPredicateExpectation(
      predicate:
        NSPredicate(format: "value == %@", text), object: editor)
    wait(for: [loaded], timeout: 5)
  }

  private func expectFile(_ url: URL, text: String) {
    let saved = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        (try? Data(contentsOf: url)) == Data(text.utf8)
      }, object: nil)
    wait(for: [saved], timeout: 5)
  }
}
