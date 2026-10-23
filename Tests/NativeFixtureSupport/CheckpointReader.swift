import CryptoKit
import Foundation
import NoteHushCore

/// Independent fixture-only reader: do not call the production manifest decoder
/// or contend with the running app's writer lock. Accept only a stable generation.
public enum CheckpointReader {
  enum Failure: Error { case invalidCheckpoint }
  private struct Envelope: Decodable {
    let version: Int
    let payload: Data
    let sha256: String
  }

  public static func read(_ primary: URL) throws -> WorkspaceSnapshot? {
    let raw = try Data(contentsOf: primary)
    do {
      let envelope = try JSONDecoder().decode(Envelope.self, from: raw)
      guard envelope.version == 6,
        Data(SHA256.hash(data: envelope.payload)).base64EncodedString() == envelope.sha256,
        var payload = try JSONSerialization.jsonObject(with: envelope.payload) as? [String: Any],
        let tabs = payload["tabs"] as? [[String: Any]]
      else { throw Failure.invalidCheckpoint }
      var totalBytes = 0
      func hydrate(_ tab: [String: Any]) throws -> [String: Any] {
        guard let identifier = tab["id"] as? String, let id = UUID(uuidString: identifier),
          id.uuidString == identifier, let reference = tab["content"] as? [String: Any],
          let digest = reference["sha256"] as? String, digest.utf8.count == 64,
          digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
          let bytes = reference["utf8Count"] as? Int, let units = reference["utf16Count"] as? Int,
          (0...(256 * 1024 * 1024)).contains(bytes), (0...bytes).contains(units),
          totalBytes <= 256 * 1024 * 1024 - bytes
        else { throw Failure.invalidCheckpoint }
        totalBytes += bytes
        let blob = primary.deletingLastPathComponent().appending(
          path: "blob-\(identifier)-\(digest).utf8")
        let data = try Data(contentsOf: blob)
        let text = String(decoding: data, as: UTF8.self)
        let actualDigest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == bytes, actualDigest == digest, text.utf8.elementsEqual(data),
          text.utf16.count == units
        else { throw Failure.invalidCheckpoint }
        var inline = tab
        inline["content"] = nil
        inline["text"] = text
        return inline
      }
      payload["tabs"] = try tabs.map(hydrate)
      if let closed = payload["closedTabs"] {
        guard let values = closed as? [[String: Any]] else { throw Failure.invalidCheckpoint }
        payload["closedTabs"] = try values.map { value in
          guard let tab = value["tab"] as? [String: Any] else { throw Failure.invalidCheckpoint }
          var result = value
          result["tab"] = try hydrate(tab)
          return result
        }
      }
      let snapshot = try JSONDecoder().decode(
        WorkspaceSnapshot.self, from: JSONSerialization.data(withJSONObject: payload))
      try snapshot.validate()
      guard try Data(contentsOf: primary) == raw else { return nil }
      return snapshot
    } catch {
      // GC may have reclaimed a blob belonging to an older observed manifest.
      // Retry only an actual publication race; stable corruption must fail.
      if let latest = try? Data(contentsOf: primary), latest != raw { return nil }
      throw error
    }
  }
}
