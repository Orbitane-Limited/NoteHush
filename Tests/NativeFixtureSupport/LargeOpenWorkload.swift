import Foundation

/// Generated input for a host-only performance workload, never an app dependency.
public enum LargeOpenWorkload: String, CaseIterable, Codable, Sendable {
  case ascii, mixed, arabicEmojiParagraph

  /// Regular launch measurements keep the two established workloads. The
  /// pathological paragraph is only selected by the bounded #75 diagnostic.
  public static var allCases: [LargeOpenWorkload] { [.ascii, .mixed] }

  public static let byteCount = 10 * 1024 * 1024
  public static let observations = 20

  public func text(byteCount: Int = Self.byteCount) throws -> String {
    guard byteCount >= 16, byteCount <= Self.byteCount else {
      throw Failure.invalidFixtureSize
    }
    let header: String
    let unit: String
    let stride: Int
    switch self {
    case .ascii:
      header = "file-000000000\r\n"
      unit = "generated line\r\n"
      stride = 16
    case .mixed:
      header = "file-000000000\r\n"
      unit = "خط e\u{301} 📝.\r\n"
      stride = 16
    case .arabicEmojiParagraph:
      header = "123456789012345\n"
      unit = "خط📝"
      stride = 8
    }
    guard byteCount.isMultiple(of: stride) else { throw Failure.invalidFixtureSize }
    // Each repeated unit fits exactly, preserving scalars, combining marks,
    // emoji and CRLF boundaries in the established line based fixtures.
    let result = header + String(repeating: unit, count: (byteCount - header.utf8.count) / stride)
    guard result.utf8.count == byteCount else { throw Failure.invalidFixtureSize }
    return result
  }

  public enum Failure: Error { case invalidFixtureSize }
}
