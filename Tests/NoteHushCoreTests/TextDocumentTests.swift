import Foundation
import XCTest

@testable import NoteHushCore

final class TextDocumentTests: XCTestCase {
  func testEveryEncodingPreservesUnicodeAndMixedNewlinesByteForByte() throws {
    for text in [
      "Hello 👩🏽‍💻 اردو e\u{301}\r\nLF\nCR\rtail\n", "",
      String(repeating: "long", count: 8192),
    ] {
      for encoding in TextFileEncoding.allCases {
        let bytes = try TextDocumentCodec.encode(text, as: encoding)
        let decoded = try TextDocumentCodec.decode(bytes)
        XCTAssertEqual(decoded.encoding, encoding)
        XCTAssertEqual(Array(decoded.text.utf8), Array(text.utf8))
        XCTAssertEqual(try TextDocumentCodec.encode(decoded.text, as: decoded.encoding), bytes)
      }
    }
  }

  func testKnownBOMAndEndianFixtures() throws {
    let fixtures: [(TextFileEncoding, [UInt8])] = [
      (.utf8, [0x41, 0x0D, 0x0A]), (.utf8BOM, [0xEF, 0xBB, 0xBF, 0x41, 0x0D, 0x0A]),
      (.utf16LE, [0xFF, 0xFE, 0x41, 0, 0x0D, 0, 0x0A, 0]),
      (.utf16BE, [0xFE, 0xFF, 0, 0x41, 0, 0x0D, 0, 0x0A]),
    ]
    for (encoding, bytes) in fixtures {
      XCTAssertEqual(try TextDocumentCodec.encode("A\r\n", as: encoding), Data(bytes))
      XCTAssertEqual(try TextDocumentCodec.decode(Data(bytes)).text, "A\r\n")
    }
  }

  func testLeadingMarkersPreserveBytesAndLiteralMarkerAfterBOM() throws {
    for encoding in [TextFileEncoding.utf8BOM, .utf16LE, .utf16BE] {
      let text = "\u{FEFF}literal marker"
      let bytes = try TextDocumentCodec.encode(text, as: encoding)
      let decoded = try TextDocumentCodec.decode(bytes)
      XCTAssertEqual(Array(decoded.text.utf8), Array(text.utf8))
      XCTAssertEqual(try TextDocumentCodec.encode(decoded.text, as: decoded.encoding), bytes)
    }
    // An initial UTF-8 U+FEFF is indistinguishable from a BOM. Interpret it as
    // the encoding marker, while preserving every original byte on Save.
    let bytes = Data("\u{FEFF}text".utf8)
    let decoded = try TextDocumentCodec.decode(bytes)
    XCTAssertEqual(decoded.encoding, .utf8BOM)
    XCTAssertEqual(decoded.text, "text")
    XCTAssertEqual(try TextDocumentCodec.encode(decoded.text, as: decoded.encoding), bytes)
  }

  func testInvalidAndUnsupportedEncodingsAreRejectedWithoutReplacementCharacters() {
    let invalid: [[UInt8]] = [
      [0xC0, 0xAF], [0xED, 0xA0, 0x80], [0xF0, 0x9F], [0xFF],
      [0xFF, 0xFE, 0x41], [0xFF, 0xFE, 0, 0xD8], [0xFE, 0xFF, 0xDC, 0],
      [0xFF, 0xFE, 0, 0xD8, 0x41, 0], [0xFF, 0xFE, 0, 0, 0x41, 0, 0, 0],
    ]
    for bytes in invalid {
      XCTAssertThrowsError(try TextDocumentCodec.decode(Data(bytes))) {
        XCTAssertEqual($0 as? TextFileError, .invalidEncoding)
      }
    }
  }

  func testBinaryControlsAreRejectedButTextWhitespaceIsPreserved() throws {
    for text in ["a\0b", "\u{1B}escape", "\u{01}"] {
      XCTAssertThrowsError(try TextDocumentCodec.decode(Data(text.utf8)))
      XCTAssertThrowsError(try TextDocumentCodec.encode(text, as: .utf8))
    }
    XCTAssertEqual(try TextDocumentCodec.decode(Data("\t\r\n\u{0C}".utf8)).text, "\t\r\n\u{0C}")
  }

  func testDirtyDigestsDistinguishCanonicallyEquivalentUnicodeBytes() {
    XCTAssertNotEqual(TextDocumentCodec.textDigest("é"), TextDocumentCodec.textDigest("e\u{301}"))
  }
}
