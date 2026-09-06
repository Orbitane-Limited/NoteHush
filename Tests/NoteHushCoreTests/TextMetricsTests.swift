import XCTest

@testable import NoteHushCore

final class TextMetricsTests: XCTestCase {
  func testEmptyAndOutOfBoundsRanges() throws {
    let metrics = try TextMetrics("")
    XCTAssertEqual(metrics.characterCount, 0)
    XCTAssertEqual(metrics.lineCount, 1)
    XCTAssertEqual(metrics.position(atUTF16Offset: Int.max), TextPosition(line: 1, column: 1))
    XCTAssertEqual(metrics.selectedCharacterCount(in: .init(location: 0, length: Int.max)), 0)
    XCTAssertEqual(metrics.utf16Offset(forLine: 1), 0)
    XCTAssertNil(metrics.utf16Offset(forLine: 0))
    XCTAssertNil(metrics.utf16Offset(forLine: 2))
    XCTAssertTrue(metrics.newlineKinds.isEmpty)
  }

  func testUnicodePositionsSelectionsAndMixedNewlines() throws {
    let text = "A👩🏽‍💻e\u{301}\r\nاردو\nZ\rQ\u{85}R\u{2028}S\u{2029}"
    let metrics = try TextMetrics(text)
    XCTAssertEqual(metrics.characterCount, text.count)
    XCTAssertEqual(metrics.utf16Count, text.utf16.count)
    XCTAssertEqual(metrics.lineCount, 7)
    XCTAssertEqual(metrics.newlineKinds, Set(TextNewline.allCases))
    XCTAssertEqual(metrics.position(atUTF16Offset: 1), TextPosition(line: 1, column: 2))
    XCTAssertEqual(metrics.position(atUTF16Offset: 4), TextPosition(line: 1, column: 2))
    let secondLine = (text as NSString).range(of: "اردو").location
    XCTAssertEqual(metrics.utf16Offset(forLine: 2), secondLine)
    XCTAssertEqual(metrics.position(atUTF16Offset: secondLine), TextPosition(line: 2, column: 1))
    XCTAssertEqual(metrics.position(atUTF16Offset: Int.max), TextPosition(line: 7, column: 1))
    XCTAssertEqual(metrics.position(atUTF16Offset: -100), TextPosition(line: 1, column: 1))
    XCTAssertEqual(metrics.selectedCharacterCount(in: .init(location: 1, length: 7)), 1)
    XCTAssertEqual(metrics.selectedCharacterCount(in: .init(location: 2, length: 1)), 1)
    XCTAssertEqual(metrics.selectedCharacterCount(in: .init(location: 2, length: 0)), 0)
    XCTAssertEqual(
      metrics.selectedCharacterCount(in: .init(location: 0, length: Int.max)), text.count)
    XCTAssertEqual(metrics.selectedCharacterCount(in: .init(location: Int.max, length: Int.max)), 0)
  }

  func testSparseIndexAgainstIndependentLinearOracle() throws {
    let text = String(repeating: "ab👨‍👩‍👧‍👦e\u{301}\r\nاردو\n\t🇵🇰\r", count: 200)
    let metrics = try TextMetrics(text)
    var offset = 0
    var line = 1
    var column = 1
    var starts = [0]
    let newlineCharacters: Set<Character> = ["\n", "\r", "\r\n"]
    for character in text {
      let width = String(character).utf16.count
      for inner in 0..<width {
        XCTAssertEqual(
          metrics.position(atUTF16Offset: offset + inner), TextPosition(line: line, column: column))
        XCTAssertEqual(
          metrics.selectedCharacterCount(in: .init(location: offset + inner, length: 1)), 1)
      }
      offset += width
      if newlineCharacters.contains(character) {
        line += 1
        column = 1
        starts.append(offset)
      } else {
        column += 1
      }
    }
    for (index, start) in starts.enumerated() {
      XCTAssertEqual(metrics.utf16Offset(forLine: index + 1), start)
    }
    XCTAssertEqual(
      metrics.position(atUTF16Offset: offset), TextPosition(line: line, column: column))
  }

  func testLongLineAndPathologicalCombiningCluster() throws {
    let prefix = String(repeating: "x", count: 1023)
    let cluster = "e" + String(repeating: "\u{301}", count: 100_000)
    let text = prefix + cluster + "\r\nlast"
    let metrics = try TextMetrics(text)
    XCTAssertEqual(metrics.characterCount, 1029)
    XCTAssertEqual(metrics.position(atUTF16Offset: 50_000), TextPosition(line: 1, column: 1024))
    XCTAssertEqual(metrics.selectedCharacterCount(in: .init(location: 2000, length: 90_000)), 1)
    XCTAssertEqual(metrics.utf16Offset(forLine: 2), prefix.utf16.count + cluster.utf16.count + 2)
    XCTAssertEqual(metrics.position(atUTF16Offset: Int.max), TextPosition(line: 2, column: 5))
  }

  func testCancelledAnalysisCannotReturnAResult() async {
    let operation = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await BackgroundTextAnalyzer().analyze(String(repeating: "abc\n", count: 100_000))
    }
    do {
      _ = try await operation.value
      XCTFail("Cancelled analysis returned a result")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
  }
}
