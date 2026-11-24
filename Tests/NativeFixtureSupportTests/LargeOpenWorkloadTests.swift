import Foundation
import NativeFixtureSupport
import XCTest

final class LargeOpenWorkloadTests: XCTestCase {
  func testSmallFixturesHaveExactIndependentByteOracles() throws {
    XCTAssertEqual(
      Data(try LargeOpenWorkload.ascii.text(byteCount: 32).utf8),
      Data("file-000000000\r\ngenerated line\r\n".utf8))
    XCTAssertEqual(
      Data(try LargeOpenWorkload.mixed.text(byteCount: 32).utf8),
      Data("file-000000000\r\nخط e\u{301} 📝.\r\n".utf8))
    XCTAssertEqual(
      Data(try LargeOpenWorkload.arabicEmojiParagraph.text(byteCount: 32).utf8),
      Data("123456789012345\nخط📝خط📝".utf8))
    XCTAssertEqual(LargeOpenWorkload.allCases, [.ascii, .mixed])
  }

  func testFullWorkloadsHaveTenMiBAndKnownUnicodeDistributions() throws {
    let ascii = try LargeOpenWorkload.ascii.text()
    let mixed = try LargeOpenWorkload.mixed.text()
    let paragraph = try LargeOpenWorkload.arabicEmojiParagraph.text()
    XCTAssertEqual(ascii.utf8.count, 10_485_760)
    XCTAssertEqual(mixed.utf8.count, 10_485_760)
    XCTAssertEqual(ascii.utf16.count, 10_485_760)
    XCTAssertEqual(mixed.utf16.count, 7_208_965)
    XCTAssertTrue(ascii.unicodeScalars.allSatisfy { $0.isASCII })
    XCTAssertTrue(mixed.contains("خط e\u{301} 📝.\r\n"))
    XCTAssertEqual(ascii.utf8.filter { $0 == 0x0A }.count, 655_360)
    XCTAssertEqual(mixed.utf8.filter { $0 == 0x0D }.count, 655_360)
    XCTAssertTrue(ascii.hasSuffix("\r\n"))
    XCTAssertTrue(mixed.hasSuffix("\r\n"))
    XCTAssertEqual(paragraph.utf8.count, LargeOpenWorkload.byteCount)
    XCTAssertTrue(paragraph.hasPrefix("123456789012345\nخط📝"))
    XCTAssertFalse(paragraph.dropFirst(16).contains("\n"))
  }

  func testInvalidOrOversizedFixtureRequestsFail() {
    for workload in LargeOpenWorkload.allCases + [.arabicEmojiParagraph] {
      for count in [Int.min, -1, 0, 15, 17, LargeOpenWorkload.byteCount + 16, Int.max] {
        XCTAssertThrowsError(try workload.text(byteCount: count))
      }
    }
  }
}
