import AppKit
import NoteHushCore
import XCTest

@MainActor
final class EditorNavigationTests: XCTestCase {
  func testLateAnalysisCannotOverwriteNewerTextOrEmptyStatus() async throws {
    _ = NSApplication.shared
    let analyzer = GatedTextAnalyzer()
    let tab = EditorTab(snapshot: TabSnapshot(text: "old"), analyzer: analyzer)
    tab.activateStatus()
    await analyzer.waitForCalls(1)
    let oldAnalysis = Task { await tab.waitForAnalysis() }
    await Task.yield()
    tab.editor.insertText("new\ntext", replacementRange: NSRange(location: 0, length: 3))
    XCTAssertNil(tab.metrics)
    await analyzer.waitForCalls(2)
    await analyzer.release(1)
    await tab.waitForAnalysis()
    XCTAssertEqual(tab.metrics?.characterCount, 8)
    XCTAssertEqual(tab.metrics?.lineCount, 2)
    await analyzer.release(0)
    await oldAnalysis.value
    XCTAssertEqual(tab.metrics?.characterCount, 8)
    tab.editor.insertText("", replacementRange: NSRange(location: 0, length: 8))
    XCTAssertEqual(tab.metrics?.characterCount, 0)
    XCTAssertEqual(tab.metrics?.lineCount, 1)
    tab.deactivateStatus()
  }

  func testCaretMovementDoesNotAnalyzeAgainAndInactiveTabRejectsLateResult() async throws {
    _ = NSApplication.shared
    let analyzer = GatedTextAnalyzer()
    let tab = EditorTab(snapshot: TabSnapshot(text: "👩🏽‍💻\nsecond"), analyzer: analyzer)
    tab.activateStatus()
    await analyzer.waitForCalls(1)
    tab.deactivateStatus()
    await analyzer.release(0)
    await tab.waitForAnalysis()
    XCTAssertNil(tab.metrics)
    tab.activateStatus()
    await analyzer.waitForCalls(2)
    await analyzer.release(1)
    await tab.waitForAnalysis()
    for offset in 0...tab.editor.string.utf16.count {
      tab.editor.setSelectedRange(NSRange(location: offset, length: 0))
    }
    tab.deactivateStatus()
    tab.activateStatus()
    let calls = await analyzer.callCount
    XCTAssertEqual(calls, 2)
    XCTAssertEqual(tab.metrics?.lineCount, 2)
    tab.deactivateStatus()
  }

  func testGoToLineValidationWhileIndexIsPending() {
    _ = NSApplication.shared
    let sheet = GoToLineSheet(line: 1, lineCount: nil)
    XCTAssertFalse(sheet.alert.buttons[0].isEnabled)
    sheet.update(lineCount: 3)
    XCTAssertTrue(sheet.alert.buttons[0].isEnabled)
    for invalid in ["", "0", "4", "-1", "1.5", "abc", String(repeating: "9", count: 40)] {
      sheet.field.stringValue = invalid
      sheet.controlTextDidChange(Notification(name: NSText.didChangeNotification))
      XCTAssertNil(sheet.selectedLine)
      XCTAssertFalse(sheet.alert.buttons[0].isEnabled)
    }
    sheet.field.stringValue = " 3 "
    sheet.controlTextDidChange(Notification(name: NSText.didChangeNotification))
    XCTAssertEqual(sheet.selectedLine, 3)
    XCTAssertTrue(sheet.alert.buttons[0].isEnabled)
  }
}

private actor GatedTextAnalyzer: TextAnalyzing {
  private var pending: [Int: CheckedContinuation<TextMetrics, any Error>] = [:]
  private var texts: [String] = []
  private var observer: (count: Int, continuation: CheckedContinuation<Void, Never>)?
  var callCount: Int { texts.count }

  func analyze(_ text: String) async throws -> TextMetrics {
    let index = texts.count
    texts.append(text)
    return try await withCheckedThrowingContinuation { continuation in
      pending[index] = continuation
      if let observer, texts.count >= observer.count {
        observer.continuation.resume()
        self.observer = nil
      }
    }
  }

  func waitForCalls(_ count: Int) async {
    if texts.count >= count { return }
    await withCheckedContinuation { observer = (count, $0) }
  }

  func release(_ index: Int) {
    do {
      pending.removeValue(forKey: index)?.resume(returning: try TextMetrics(texts[index]))
    } catch { pending.removeValue(forKey: index)?.resume(throwing: error) }
  }
}
