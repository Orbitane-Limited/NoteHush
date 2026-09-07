import CryptoKit
import Foundation

@testable import NoteHushCore

/// Real schema-1...5 payloads contain inline text, never schema-6 references.
func legacyRecoveryEnvelope(_ snapshot: WorkspaceSnapshot, version: Int) throws -> Data {
  precondition((1...5).contains(version))
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  let payload = try encoder.encode(snapshot)
  return try JSONSerialization.data(
    withJSONObject: [
      "version": version, "payload": payload.base64EncodedString(),
      "sha256": Data(SHA256.hash(data: payload)).base64EncodedString(),
    ], options: [.sortedKeys])
}
