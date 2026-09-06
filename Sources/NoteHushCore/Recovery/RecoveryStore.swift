import CryptoKit
import Foundation

public enum RecoveryError: Error, Equatable, Sendable {
  case storageUnavailable
  case busy
  case corruptGenerations
  case unsupportedSchema(Int)
  case staleRevision
  case conflictingRevision
  case snapshotTooLarge
}

public enum RecoverySource: Sendable {
  case newWorkspace
  case primary
  case previous
}

public struct RecoveryLoad: Sendable {
  public let snapshot: WorkspaceSnapshot?
  public let source: RecoverySource
  public let foundDamagedGeneration: Bool
}

public enum RecoveryCommit: Sendable {
  case saved
  case unchanged
}

/// Serializes checkpoint work away from the UI. Disk locking also protects against
/// a second store instance/process; every commit rechecks the latest disk revision.
public actor RecoveryStore {
  static let primaryName = "session.json"
  static let previousName = "session.previous.json"
  static let formatVersion = 5
  static let maximumEnvelopeBytes = 256 * 1024 * 1024

  private let files: any RecoveryFiles

  public init(directory: URL) {
    files = DiskRecoveryFiles(directory: directory)
  }

  init(files: any RecoveryFiles) {
    self.files = files
  }

  public func load() throws -> RecoveryLoad {
    try files.withExclusiveAccess {
      let inspection = try inspect()
      return RecoveryLoad(
        snapshot: inspection.current?.snapshot, source: inspection.source,
        foundDamagedGeneration: !inspection.damaged.isEmpty)
    }
  }

  /// Lossless export of both on-disk generations, including unknown schemas.
  /// Export never interprets or changes the source files.
  public func exportGenerations() throws -> Data {
    try files.withExclusiveAccess {
      var generations: [String: Data] = [:]
      for name in [Self.primaryName, Self.previousName] {
        generations[name] = try files.read(name)
      }
      return try Self.encoder().encode(generations)
    }
  }

  @discardableResult
  public func commit(_ snapshot: WorkspaceSnapshot) throws -> RecoveryCommit {
    try snapshot.validate()
    let payload = try Self.encoder().encode(snapshot)
    let encoded = try Self.encoder().encode(
      Envelope(version: Self.formatVersion, payload: payload, sha256: Self.digest(payload)))
    guard encoded.count <= Self.maximumEnvelopeBytes else { throw RecoveryError.snapshotTooLarge }

    return try files.withExclusiveAccess {
      let inspection = try inspect()
      let retained = Set(snapshot.tabs.map(\.id) + (snapshot.closedTabs ?? []).map { $0.tab.id })
      let needsPruning = inspection.candidates.contains { candidate in
        let previousTabs =
          candidate.snapshot.tabs + (candidate.snapshot.closedTabs ?? []).map(\.tab)
        return previousTabs.contains { !retained.contains($0.id) }
      }
      if let current = inspection.current {
        guard snapshot.revision >= current.snapshot.revision else {
          throw RecoveryError.staleRevision
        }
        if snapshot.revision == current.snapshot.revision {
          guard payload == current.canonicalPayload else { throw RecoveryError.conflictingRevision }
          // Retry interrupted post-commit cleanup even if the primary is already current.
          if needsPruning { try files.writeAtomically(encoded, named: Self.previousName) }
          return .unchanged
        }
      }

      // Keep damaged bytes before replacing their slots. Never delete the only
      // evidence of failed recovery, even when a verified fallback exists.
      for (name, data) in inspection.damaged {
        try files.writeAtomically(data, named: "damaged-\(UUID().uuidString)-\(name)")
      }
      // Publishing the backup first makes interruption between the two writes safe.
      // The first checkpoint also gets a duplicate so it has a recovery fallback.
      try files.writeAtomically(inspection.current?.raw ?? encoded, named: Self.previousName)
      try files.writeAtomically(encoded, named: Self.primaryName)
      // Only after publication may an evicted/cleared draft leave the backup.
      // An interrupted cleanup still leaves the newer, complete primary authoritative.
      // Damaged evidence files are deliberately never erased by history clearing.
      if needsPruning { try files.writeAtomically(encoded, named: Self.previousName) }
      return .saved
    }
  }

  private struct Header: Decodable { let version: Int }

  private struct Envelope: Codable {
    let version: Int
    let payload: Data
    let sha256: String
  }

  private struct Candidate {
    let snapshot: WorkspaceSnapshot
    let canonicalPayload: Data
    let raw: Data
    let source: RecoverySource
  }

  private struct Inspection {
    let current: Candidate?
    let source: RecoverySource
    let damaged: [(String, Data)]
    let candidates: [Candidate]
  }

  private func inspect() throws -> Inspection {
    let generations: [(String, RecoverySource)] = [
      (Self.primaryName, .primary), (Self.previousName, .previous),
    ]
    var candidates: [Candidate] = []
    var damaged: [(String, Data)] = []
    for (name, source) in generations {
      guard let raw = try files.read(name) else { continue }
      do {
        // Decode the version before the payload: a future format may not even
        // contain the same fields. It must block writes, not look like corruption.
        let version = try JSONDecoder().decode(Header.self, from: raw).version
        guard (1...Self.formatVersion).contains(version) else {
          throw RecoveryError.unsupportedSchema(version)
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: raw)
        guard Self.digest(envelope.payload) == envelope.sha256 else {
          throw RecoveryError.corruptGenerations
        }
        let snapshot = try JSONDecoder().decode(WorkspaceSnapshot.self, from: envelope.payload)
        try snapshot.validate()
        candidates.append(
          Candidate(
            snapshot: snapshot, canonicalPayload: try Self.encoder().encode(snapshot),
            raw: raw, source: source))
      } catch let error as RecoveryError {
        if case .unsupportedSchema = error { throw error }
        damaged.append((name, raw))
      } catch {
        damaged.append((name, raw))
      }
    }
    guard var current = candidates.first else {
      guard damaged.isEmpty else { throw RecoveryError.corruptGenerations }
      return Inspection(current: nil, source: .newWorkspace, damaged: [], candidates: [])
    }
    for candidate in candidates.dropFirst() {
      if candidate.snapshot.revision == current.snapshot.revision,
        candidate.canonicalPayload != current.canonicalPayload
      {
        throw RecoveryError.conflictingRevision
      }
      if candidate.snapshot.revision > current.snapshot.revision { current = candidate }
    }
    return Inspection(
      current: current, source: current.source, damaged: damaged, candidates: candidates)
  }

  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  private static func digest(_ data: Data) -> String {
    Data(SHA256.hash(data: data)).base64EncodedString()
  }
}
