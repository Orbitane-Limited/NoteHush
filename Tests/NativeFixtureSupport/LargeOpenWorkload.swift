import Foundation

/// Generated input for a host-only performance workload, never an app dependency.
public enum LargeOpenWorkload: String, CaseIterable, Codable, Sendable {
  case ascii, mixed

  public static let byteCount = 10 * 1024 * 1024
  public static let observations = 20

  public func text(byteCount: Int = Self.byteCount) throws -> String {
    guard byteCount >= 16, byteCount <= Self.byteCount, byteCount.isMultiple(of: 16) else {
      throw Failure.invalidFixtureSize
    }
    // Each complete line is exactly sixteen UTF-8 bytes. Repetition therefore
    // never truncates a scalar, combining sequence, emoji or CRLF pair.
    let header = "file-000000000\r\n"
    let line = self == .ascii ? "generated line\r\n" : "خط e\u{301} 📝.\r\n"
    let result = header + String(repeating: line, count: byteCount / 16 - 1)
    guard result.utf8.count == byteCount else { throw Failure.invalidFixtureSize }
    return result
  }

  public enum Failure: Error { case invalidFixtureSize }
}
