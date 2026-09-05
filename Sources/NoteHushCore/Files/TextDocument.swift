import CryptoKit
import Foundation

public enum TextFileEncoding: String, Codable, CaseIterable, Sendable {
  case utf8, utf8BOM, utf16LE, utf16BE

  public var displayName: String {
    switch self {
    case .utf8: "UTF-8"
    case .utf8BOM: "UTF-8 with BOM"
    case .utf16LE: "UTF-16 LE with BOM"
    case .utf16BE: "UTF-16 BE with BOM"
    }
  }
}

public enum TextFileError: Error, Equatable, Sendable {
  case invalidEncoding, binaryContent, tooLarge, notRegularFile, unavailable, changedOnDisk,
    alreadyOpen
}

public struct DecodedText: Sendable {
  public let text: String
  public let encoding: TextFileEncoding
}

public enum TextDocumentCodec {
  public static let maximumFileBytes = 100 * 1024 * 1024
  public static let largeFileBytes = 20 * 1024 * 1024

  public static func decode(_ data: Data) throws -> DecodedText {
    guard data.count <= maximumFileBytes else { throw TextFileError.tooLarge }
    let encoding: TextFileEncoding
    let payload: Data
    if data.starts(with: [0xFF, 0xFE, 0, 0]) || data.starts(with: [0, 0, 0xFE, 0xFF]) {
      throw TextFileError.invalidEncoding
    } else if data.starts(with: [0xEF, 0xBB, 0xBF]) {
      encoding = .utf8BOM
      payload = data.dropFirst(3)
    } else if data.starts(with: [0xFF, 0xFE]) {
      encoding = .utf16LE
      payload = data.dropFirst(2)
    } else if data.starts(with: [0xFE, 0xFF]) {
      encoding = .utf16BE
      payload = data.dropFirst(2)
    } else {
      encoding = .utf8
      payload = data
    }
    let text: String
    if encoding == .utf16LE || encoding == .utf16BE {
      guard payload.count.isMultiple(of: 2) else { throw TextFileError.invalidEncoding }
      let units = payload.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [UInt16] in
        stride(from: 0, to: bytes.count, by: 2).map { index in
          let first = UInt16(bytes[index])
          let second = UInt16(bytes[index + 1])
          return encoding == .utf16LE ? first | (second << 8) : (first << 8) | second
        }
      }
      text = String(decoding: units, as: UTF16.self)
      // Reject repaired surrogates, and retain a literal U+FEFF after the BOM.
      guard text.utf16.elementsEqual(units) else { throw TextFileError.invalidEncoding }
    } else {
      let decoded = String(decoding: payload, as: UTF8.self)
      guard Data(decoded.utf8) == payload else { throw TextFileError.invalidEncoding }
      text = decoded
    }
    // Reject NUL and non-text C0 controls; tabs, CR/LF, and form feeds are text.
    try validateText(text)
    return DecodedText(text: text, encoding: encoding)
  }

  public static func encode(_ text: String, as encoding: TextFileEncoding) throws -> Data {
    try validateText(text)
    let byteCount: Int
    switch encoding {
    case .utf8: byteCount = text.utf8.count
    case .utf8BOM: byteCount = text.utf8.count + 3
    case .utf16LE, .utf16BE:
      guard text.utf16.count <= (maximumFileBytes - 2) / 2 else { throw TextFileError.tooLarge }
      byteCount = text.utf16.count * 2 + 2
    }
    guard byteCount <= maximumFileBytes else { throw TextFileError.tooLarge }
    var result: Data
    switch encoding {
    case .utf8: result = Data(text.utf8)
    case .utf8BOM: result = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    case .utf16LE, .utf16BE:
      result = Data(encoding == .utf16LE ? [0xFF, 0xFE] : [0xFE, 0xFF])
      result.reserveCapacity(byteCount)
      for unit in text.utf16 {
        let low = UInt8(truncatingIfNeeded: unit)
        let high = UInt8(truncatingIfNeeded: unit >> 8)
        result.append(contentsOf: encoding == .utf16LE ? [low, high] : [high, low])
      }
    }
    guard result.count <= maximumFileBytes else { throw TextFileError.tooLarge }
    return result
  }

  public static func digest(_ data: Data) -> String {
    Data(SHA256.hash(data: data)).base64EncodedString()
  }

  public static func textDigest(_ text: String) -> String { digest(Data(text.utf8)) }

  private static func validateText(_ text: String) throws {
    guard
      !text.unicodeScalars.contains(where: {
        $0.value < 32 && ![9, 10, 12, 13].contains($0.value)
      })
    else { throw TextFileError.binaryContent }
  }
}

public struct FileIdentity: Codable, Equatable, Sendable {
  public let device: Int32
  public let inode: UInt64
}

/// Metadata is a save baseline, never authority to read a recovered path.
public struct FileBinding: Codable, Equatable, Sendable {
  public let url: URL
  public let identity: FileIdentity
  public let encoding: TextFileEncoding
  public let fileDigest: String
  public let textDigest: String
}

public struct OpenedTextFile: Sendable {
  public let text: String
  public let binding: FileBinding
  public let byteCount: Int
}
