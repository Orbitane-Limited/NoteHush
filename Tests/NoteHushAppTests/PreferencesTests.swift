import AppKit
import PDFKit
import XCTest

@testable import NoteHushCore

@MainActor
final class PreferencesTests: XCTestCase {
  func testPreferencesPreserveBytesBindingUndoAndRestoreAcrossTabs() async throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appending(
      path: "NoteHushPreferences-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appending(path: "fixture.txt")
    let text = "literal \"quotes\" --\r\nاردو e\u{301} 👩🏽‍💻\nlast"
    let service = TextFileService()
    _ = try await service.save(
      text, encoding: .utf16LE, to: source, expected: nil, saveAs: true)
    let originalBytes = try Data(contentsOf: source)
    let opened = try await service.open(source)
    let recovery = root.appending(path: "Recovery")
    let workspace = WorkspaceWindowController(directory: recovery)
    workspace.showWindow(nil)
    await workspace.waitUntilLoaded()
    workspace.installFile(opened, grantedURL: source)
    let tab = try XCTUnwrap(workspace.selectedTab)
    let history = try XCTUnwrap(tab.undoManager(for: tab.editor))
    history.beginUndoGrouping()
    tab.editor.insertText("!", replacementRange: NSRange(location: text.utf16.count, length: 0))
    history.endUndoGrouping()
    let selection = tab.editor.selectedRange()
    var preferences = EditorPreferences()
    preferences.fontName = "Menlo-Bold"
    preferences.fontSize = 18
    preferences.zoomPercent = 150
    preferences.wordWrap = false
    preferences.appearance = .dark
    preferences.checksSpelling = true
    workspace.applyPreferences(preferences)
    XCTAssertEqual(tab.editor.string, text + "!")
    XCTAssertEqual(tab.editor.selectedRange(), selection)
    XCTAssertEqual(tab.file, opened.binding)
    XCTAssertEqual(tab.editor.font?.fontName, "Menlo-Bold")
    XCTAssertEqual(tab.editor.font?.pointSize, 27)
    XCTAssertFalse(tab.editor.textContainer?.widthTracksTextView ?? true)
    XCTAssertTrue(tab.scrollView.hasHorizontalScroller)
    XCTAssertTrue(tab.editor.isContinuousSpellCheckingEnabled)
    XCTAssertEqual(workspace.window?.appearance?.name, .darkAqua)
    history.undo()
    XCTAssertEqual(Array(tab.editor.string.utf8), Array(text.utf8))
    await tab.waitForDirtyState()
    XCTAssertFalse(tab.isDirty)
    workspace.newTab(nil)
    XCTAssertEqual(workspace.selectedTab?.editor.font, tab.editor.font)
    workspace.previousTab(nil)
    await workspace.prepareToQuit()
    workspace.close()
    let restored = WorkspaceWindowController(directory: recovery)
    restored.showWindow(nil)
    await restored.waitUntilLoaded()
    XCTAssertEqual(restored.preferences, preferences)
    XCTAssertEqual(restored.selectedTab?.editor.font?.pointSize, 27)
    let recovered = try XCTUnwrap(restored.selectedTab)
    XCTAssertEqual(recovered.file, opened.binding)
    _ = try await service.save(
      recovered.editor.string, encoding: opened.binding.encoding, to: source,
      expected: opened.binding, saveAs: false)
    XCTAssertEqual(try Data(contentsOf: source), originalBytes)
    await restored.prepareToQuit()
    restored.close()
  }

  func testDisplayChangesKeepMarkedTextAndDisableAutomaticSubstitutions() {
    _ = NSApplication.shared
    let tab = EditorTab(snapshot: TabSnapshot(text: "start "))
    tab.editor.setMarkedText(
      "にほん", selectedRange: NSRange(location: 3, length: 0),
      replacementRange: NSRange(location: 6, length: 0))
    let marked = tab.editor.markedRange()
    let selection = tab.editor.selectedRange()
    var preferences = EditorPreferences()
    preferences.fontSize = 20
    preferences.wordWrap = false
    preferences.checksSpelling = true
    tab.applyPreferences(preferences)
    XCTAssertTrue(tab.editor.hasMarkedText())
    XCTAssertEqual(tab.editor.markedRange(), marked)
    XCTAssertEqual(tab.editor.selectedRange(), selection)
    XCTAssertEqual(tab.editor.string, "start にほん")
    XCTAssertFalse(tab.editor.isAutomaticQuoteSubstitutionEnabled)
    XCTAssertFalse(tab.editor.isAutomaticDashSubstitutionEnabled)
    XCTAssertFalse(tab.editor.isAutomaticTextReplacementEnabled)
    XCTAssertFalse(tab.editor.isAutomaticSpellingCorrectionEnabled)
    XCTAssertEqual(tab.editor.inlinePredictionType, .no)
    XCTAssertFalse(tab.editor.isAutomaticTextCompletionEnabled)
    XCTAssertTrue(tab.editor.isContinuousSpellCheckingEnabled)
    if #available(macOS 15.0, *) {
      XCTAssertEqual(tab.editor.mathExpressionCompletionType, .no)
      XCTAssertEqual(tab.editor.writingToolsBehavior, .none)
    }
    tab.editor.insertText("日本", replacementRange: NSRange(location: NSNotFound, length: 0))
    XCTAssertFalse(tab.editor.hasMarkedText())
    XCTAssertEqual(tab.editor.string, "start 日本")
  }

  func testNoWrapHorizontalScrollAndSelectionSurviveTabSwitchAndRestart() async throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appending(path: "NoteHushWrap-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    var preferences = EditorPreferences()
    preferences.wordWrap = false
    let tab = TabSnapshot(
      text: String(repeating: "long line ", count: 500), selection: TextSelection(location: 400))
    let seed = WorkspaceSnapshot(
      revision: 1, tabs: [tab], selectedTabID: tab.id, preferences: preferences)
    try await RecoveryStore(directory: root).commit(seed)
    let workspace = WorkspaceWindowController(directory: root)
    workspace.showWindow(nil)
    await workspace.waitUntilLoaded()
    let editor = try XCTUnwrap(workspace.selectedTab)
    XCTAssertGreaterThan(editor.editor.frame.width, editor.scrollView.contentSize.width)
    editor.scrollView.contentView.scroll(to: NSPoint(x: 500, y: 0))
    editor.scrollView.reflectScrolledClipView(editor.scrollView.contentView)
    workspace.newTab(nil)
    workspace.previousTab(nil)
    XCTAssertEqual(editor.scrollView.contentView.bounds.minX, 500, accuracy: 1)
    await workspace.prepareToQuit()
    workspace.close()
    let restored = WorkspaceWindowController(directory: root)
    restored.showWindow(nil)
    await restored.waitUntilLoaded()
    XCTAssertEqual(
      try XCTUnwrap(restored.selectedTab).scrollView.contentView.bounds.minX, 500, accuracy: 1)
    XCTAssertEqual(restored.selectedTab?.editor.selectedRange().location, 400)
    restored.toggleWordWrap()
    XCTAssertEqual(
      restored.selectedTab?.editor.frame.width ?? 0,
      restored.selectedTab?.scrollView.contentSize.width ?? 1, accuracy: 1)
    XCTAssertEqual(restored.selectedTab?.scrollView.contentView.bounds.minX, 0)
    await restored.prepareToQuit()
    restored.close()
  }

  func testPrintedPDFPaginatesEveryLineAndIgnoresScreenZoomAndWrap() throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appending(path: "NoteHushPrint-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let lines = (1...240).map {
      "LINE-\(String(format: "%03d", $0)) café wrapped text "
        + String(repeating: "word ", count: 14)
    }
    var preferences = EditorPreferences()
    preferences.zoomPercent = 300
    preferences.wordWrap = false
    preferences.appearance = .dark
    let view = PrintDocumentView(
      text: lines.joined(separator: "\n"), font: preferences.font(zoomed: false))
    let info = WorkspacePrinter.defaultPrintInfo()
    info.paperSize = NSSize(width: 612, height: 792)
    info.jobDisposition = .save
    let output = root.appending(path: "fixture.pdf")
    info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
    let operation = NSPrintOperation(view: view, printInfo: info)
    operation.showsPrintPanel = false
    operation.showsProgressPanel = false
    XCTAssertTrue(operation.run())
    let pdf = try XCTUnwrap(PDFDocument(url: output))
    XCTAssertGreaterThan(pdf.pageCount, 3)
    XCTAssertEqual(pdf.pageCount, view.pageCount)
    let extracted = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(
      separator: "\n")
    for index in 1...240 {
      XCTAssertEqual(
        extracted.components(separatedBy: "LINE-\(String(format: "%03d", index))").count, 2)
    }
    XCTAssertTrue(extracted.contains("café"))
    XCTAssertEqual(
      extracted.split(whereSeparator: \.isWhitespace),
      lines.joined(separator: "\n").split(whereSeparator: \.isWhitespace))
    let attachment = XCTAttachment(
      data: try Data(contentsOf: output), uniformTypeIdentifier: "com.adobe.pdf")
    attachment.name = "Paginated print fixture"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, NSSize(width: 612, height: 792))
    let portraitCount = view.pageCount
    info.orientation = .landscape
    info.scalingFactor = 0.75
    try view.paginate(using: info)
    XCTAssertNotEqual(view.pageCount, portraitCount)
    let empty = PrintDocumentView(text: "", font: preferences.font(zoomed: false))
    try empty.paginate(using: info)
    XCTAssertEqual(empty.pageCount, 1)
  }

  func testUnavailableFontFallsBackAndImpossiblePageDoesNotDropText() throws {
    _ = NSApplication.shared
    var preferences = EditorPreferences()
    preferences.fontName = "NoteHush-Nonexistent-Fixture-Font"
    preferences.fontSize = 18
    XCTAssertEqual(preferences.font(), .monospacedSystemFont(ofSize: 18, weight: .regular))
    let view = PrintDocumentView(text: "Do not truncate this text", font: .systemFont(ofSize: 72))
    let info = WorkspacePrinter.defaultPrintInfo()
    info.paperSize = NSSize(width: 100, height: 100)
    info.scalingFactor = 10
    XCTAssertThrowsError(try view.paginate(using: info))
    XCTAssertTrue(view.paginationFailed)
    XCTAssertEqual(view.pageCount, 0)
    info.paperSize = NSSize(width: 612, height: 792)
    info.scalingFactor = 1
    try view.paginate(using: info)
    XCTAssertFalse(view.paginationFailed)
    XCTAssertGreaterThan(view.pageCount, 0)
  }

  func testPrintCapturesActiveTabOrUnicodeSelectionWithoutChangingDraft() async throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appending(
      path: "NoteHushPrintSelection-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = WorkspaceWindowController(directory: root)
    await workspace.waitUntilLoaded()
    let first = try XCTUnwrap(workspace.selectedTab)
    first.editor.insertText("first draft", replacementRange: NSRange(location: 0, length: 0))
    workspace.newTab(nil)
    let second = try XCTUnwrap(workspace.selectedTab)
    let text = "before e\u{301} 👩🏽‍💻 اردو after"
    second.editor.insertText(text, replacementRange: NSRange(location: 0, length: 0))
    XCTAssertNil(workspace.textForPrinting(selectionOnly: true))
    let selection = (text as NSString).range(of: "e\u{301} 👩🏽‍💻 اردو")
    second.editor.setSelectedRange(selection)
    let captured = workspace.textForPrinting(selectionOnly: true)
    XCTAssertEqual(Array(try XCTUnwrap(captured).utf8), Array("e\u{301} 👩🏽‍💻 اردو".utf8))
    XCTAssertEqual(workspace.textForPrinting(selectionOnly: false), text)
    XCTAssertEqual(second.editor.selectedRange(), selection)
    second.editor.insertText("changed", replacementRange: selection)
    XCTAssertEqual(captured, "e\u{301} 👩🏽‍💻 اردو")
    workspace.previousTab(nil)
    XCTAssertEqual(workspace.textForPrinting(selectionOnly: false), "first draft")
    await workspace.prepareToQuit()
    workspace.close()
  }
}
