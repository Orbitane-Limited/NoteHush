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

/// Actor isolation serializes I/O off the UI thread. The disk lock protects
/// independent stores/processes; every commit reads both manifest revisions.
public actor RecoveryStore {
  static let primaryName = "session.json"
  static let previousName = "session.previous.json"
  static let formatVersion = 6
  static let maximumEnvelopeBytes = 256 * 1024 * 1024
  static let maximumExportBytes = 512 * 1024 * 1024

  private let files: any RecoveryFiles
  private var textReferences: [UUID: RecoveryBlobReference] = [:]
  private var verifiedBlobs: [String: VerifiedBlob] = [:]

  public init(directory: URL) { files = DiskRecoveryFiles(directory: directory) }
  package init(files: any RecoveryFiles) { self.files = files }

  public func load() throws -> RecoveryLoad {
    try withFiles {
      // A user-initiated retry or fresh load must verify actual blob bytes.
      let inspection = try inspect(hydrate: true)
      let snapshot: WorkspaceSnapshot?
      if let current = inspection.current {
        snapshot = try current.manifest.snapshot { id, reference in
          guard let text = inspection.text[reference.name(for: id)] else {
            throw RecoveryError.corruptGenerations
          }
          return text
        }
        if let snapshot { remember(snapshot, manifest: current.manifest) }
      } else {
        snapshot = nil
        textReferences = [:]
      }
      trimVerified(
        to: inspection.candidates.reduce(into: Set<String>()) {
          $0.formUnion($1.blobNames)
        })
      return RecoveryLoad(
        snapshot: snapshot, source: inspection.current?.source ?? .newWorkspace,
        foundDamagedGeneration: !inspection.damaged.isEmpty)
    }
  }

  /// Lossless raw export, including blobs, damaged bundles and interrupted writes.
  /// Do not interpret an unknown format or follow links while exporting evidence.
  public func exportGenerations() throws -> Data {
    try withFiles {
      let names = try files.names().filter { $0 != ".lock" }
      var sizes: [String: Int64] = [:]
      var total: Int64 = 0
      for name in names {
        guard let fingerprint = try files.fingerprint(name) else {
          throw RecoveryError.storageUnavailable
        }
        guard fingerprint.size <= Self.maximumEnvelopeBytes,
          total <= Int64(Self.maximumExportBytes) - fingerprint.size
        else { throw RecoveryError.snapshotTooLarge }
        total += fingerprint.size
        sizes[name] = fingerprint.size
      }
      var entries: [String: Data] = [:]
      for name in names {
        guard let data = try files.read(name), Int64(data.count) == sizes[name] else {
          throw RecoveryError.storageUnavailable
        }
        entries[name] = data
      }
      return try Self.encoder().encode(entries)
    }
  }

  @discardableResult
  public func commit(_ snapshot: WorkspaceSnapshot) throws -> RecoveryCommit {
    let manifest = try prepare(snapshot)
    let payload = try Self.encoder().encode(manifest)
    let encoded = try Self.encoder().encode(
      Envelope(version: Self.formatVersion, payload: payload, sha256: Self.digest(payload)))
    guard encoded.count <= Self.maximumEnvelopeBytes else { throw RecoveryError.snapshotTooLarge }

    return try withFiles {
      let inspection = try inspect(hydrate: false)
      let current = inspection.current
      let sameRevision = current?.manifest.revision == snapshot.revision
      if let current {
        guard snapshot.revision >= current.manifest.revision else {
          throw RecoveryError.staleRevision
        }
        if sameRevision, payload != current.canonicalPayload {
          throw RecoveryError.conflictingRevision
        }
      }
      let needsPruning = inspection.candidates.contains {
        !$0.manifest.tabIDs.isSubset(of: manifest.tabIDs)
      }

      // Copy every existing managed blob with each damaged raw generation before
      // replacement. A finite evidence bundle protects even unparseable references
      // without pinning all future revisions forever. Its raw manifest is copied last.
      for (name, raw) in inspection.damaged { try preserveGeneration(name, raw: raw) }
      try installBlobs(snapshot, manifest: manifest)

      let alreadyPublished =
        sameRevision && current?.version == Self.formatVersion
        && current?.source == .primary && inspection.candidates.count == 2
        && inspection.damaged.isEmpty
      var retained = manifest.blobNames
      if alreadyPublished {
        if needsPruning {
          try files.writeAtomically(encoded, named: Self.previousName)
        } else {
          for candidate in inspection.candidates { retained.formUnion(candidate.blobNames) }
        }
      } else {
        // All referenced text is durable before either manifest becomes visible.
        try files.writeAtomically(current?.raw ?? encoded, named: Self.previousName)
        try files.writeAtomically(encoded, named: Self.primaryName)
        // Only now can history clearing remove obsolete text from the fallback.
        if needsPruning {
          try files.writeAtomically(encoded, named: Self.previousName)
        } else if let current {
          retained.formUnion(current.blobNames)
        }
      }
      try reclaim(retaining: retained)
      // Also covers a prior rename/unlink whose directory sync failed, even when
      // retrying the same revision and there is no further mutation to perform.
      try files.synchronizeDirectory()
      trimVerified(to: retained)
      return alreadyPublished ? .unchanged : .saved
    }
  }

  private func prepare(_ snapshot: WorkspaceSnapshot) throws -> RecoveryManifest {
    var references: [UUID: RecoveryBlobReference] = [:]
    try snapshot.validate { tab in
      let reference = try textReferences[tab.textIdentity] ?? RecoveryBlobReference(text: tab.text)
      references[tab.textIdentity] = reference
      return reference.utf16Count
    }
    let manifest = try RecoveryManifest(snapshot: snapshot) { tab in
      guard let reference = references[tab.textIdentity] else {
        throw RecoveryError.corruptGenerations
      }
      return reference
    }
    try manifest.validate()
    textReferences = references
    return manifest
  }

  private func remember(_ snapshot: WorkspaceSnapshot, manifest: RecoveryManifest) {
    textReferences = [:]
    let tabs = snapshot.tabs + (snapshot.closedTabs ?? []).map(\.tab)
    for (tab, metadata) in zip(tabs, manifest.allTabs) {
      textReferences[tab.textIdentity] = metadata.content
    }
  }

  private func installBlobs(_ snapshot: WorkspaceSnapshot, manifest: RecoveryManifest) throws {
    let tabs = snapshot.tabs + (snapshot.closedTabs ?? []).map(\.tab)
    for (tab, metadata) in zip(tabs, manifest.allTabs) {
      let reference = metadata.content
      let name = reference.name(for: tab.id)
      if let fingerprint = try files.fingerprint(name) {
        if verifiedBlobs[name] == VerifiedBlob(reference: reference, fingerprint: fingerprint) {
          continue
        }
        guard let raw = try files.read(name) else { throw RecoveryError.storageUnavailable }
        if (try? reference.decode(raw)) != nil {
          guard try files.fingerprint(name) == fingerprint else {
            throw RecoveryError.storageUnavailable
          }
          verifiedBlobs[name] = VerifiedBlob(reference: reference, fingerprint: fingerprint)
          continue
        }
        // Never overwrite corrupt bytes simply because their filename is expected.
        try files.writeAtomically(raw, named: "damaged-\(UUID().uuidString)--\(name)")
      }
      try files.writeAtomically(Data(tab.text.utf8), named: name)
      guard let fingerprint = try files.fingerprint(name), fingerprint.size == reference.utf8Count
      else { throw RecoveryError.storageUnavailable }
      verifiedBlobs[name] = VerifiedBlob(reference: reference, fingerprint: fingerprint)
    }
  }

  private func preserveGeneration(_ name: String, raw: Data) throws {
    let prefix = "damaged-\(UUID().uuidString)--"
    for blob in try files.names() where RecoveryBlobReference.isManagedName(blob) {
      guard let data = try files.read(blob) else { throw RecoveryError.storageUnavailable }
      try files.writeAtomically(data, named: prefix + blob)
    }
    try files.writeAtomically(raw, named: prefix + name)
  }

  private func reclaim(retaining names: Set<String>) throws {
    for name in try files.names()
    where RecoveryBlobReference.isManagedName(name) && !names.contains(name) {
      try files.remove(name)
      verifiedBlobs[name] = nil
    }
  }

  private func trimVerified(to names: Set<String>) {
    verifiedBlobs = verifiedBlobs.filter { names.contains($0.key) }
  }

  private func withFiles<T>(_ operation: () throws -> T) throws -> T {
    do { return try files.withExclusiveAccess(operation) } catch {
      // No I/O failure or cross-store conflict leaves optimistic cache state behind.
      verifiedBlobs = [:]
      textReferences = [:]
      throw error
    }
  }

  private struct Header: Decodable { let version: Int }
  private struct Envelope: Codable {
    let version: Int
    let payload: Data
    let sha256: String
  }
  private struct VerifiedBlob: Equatable {
    let reference: RecoveryBlobReference
    let fingerprint: RecoveryFileFingerprint
  }
  private struct Candidate {
    let manifest: RecoveryManifest
    let canonicalPayload: Data
    let raw: Data
    let source: RecoverySource
    let version: Int
    var blobNames: Set<String> { version == formatVersion ? manifest.blobNames : [] }
  }
  private struct Inspection {
    let current: Candidate?
    let damaged: [(String, Data)]
    let candidates: [Candidate]
    let text: [String: String]
  }

  private func inspect(hydrate: Bool) throws -> Inspection {
    var candidates: [Candidate] = []
    var damaged: [(String, Data)] = []
    var text: [String: String] = [:]
    var checked: [String: RecoveryBlobReference] = [:]
    for (name, source) in [
      (Self.primaryName, RecoverySource.primary), (Self.previousName, .previous),
    ] {
      guard let raw = try files.read(name) else { continue }
      do {
        let version = try JSONDecoder().decode(Header.self, from: raw).version
        guard (1...Self.formatVersion).contains(version) else {
          throw RecoveryError.unsupportedSchema(version)
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: raw)
        guard Self.digest(envelope.payload) == envelope.sha256 else {
          throw RecoveryError.corruptGenerations
        }
        let manifest: RecoveryManifest
        if version < Self.formatVersion {
          let snapshot = try JSONDecoder().decode(WorkspaceSnapshot.self, from: envelope.payload)
          try snapshot.validate()
          manifest = try RecoveryManifest(snapshot: snapshot) { tab in
            let reference = try RecoveryBlobReference(text: tab.text)
            if hydrate { text[reference.name(for: tab.id)] = tab.text }
            return reference
          }
        } else {
          manifest = try JSONDecoder().decode(RecoveryManifest.self, from: envelope.payload)
        }
        try manifest.validate()
        if version == Self.formatVersion {
          for tab in manifest.allTabs {
            let name = tab.content.name(for: tab.id)
            if checked[name] == tab.content { continue }
            let decoded = try verifyBlob(name, reference: tab.content, hydrate: hydrate)
            if let decoded { text[name] = decoded }
            checked[name] = tab.content
          }
        }
        candidates.append(
          Candidate(
            manifest: manifest, canonicalPayload: try Self.encoder().encode(manifest),
            raw: raw, source: source, version: version))
      } catch let error as RecoveryError {
        switch error {
        case .unsupportedSchema, .storageUnavailable, .busy: throw error
        default: damaged.append((name, raw))
        }
      } catch { damaged.append((name, raw)) }
    }
    guard var current = candidates.first else {
      guard damaged.isEmpty else { throw RecoveryError.corruptGenerations }
      return Inspection(current: nil, damaged: [], candidates: [], text: [:])
    }
    for candidate in candidates.dropFirst() {
      if candidate.manifest.revision == current.manifest.revision,
        candidate.canonicalPayload != current.canonicalPayload
      {
        throw RecoveryError.conflictingRevision
      }
      if candidate.manifest.revision > current.manifest.revision { current = candidate }
    }
    return Inspection(current: current, damaged: damaged, candidates: candidates, text: text)
  }

  private func verifyBlob(_ name: String, reference: RecoveryBlobReference, hydrate: Bool) throws
    -> String?
  {
    guard let fingerprint = try files.fingerprint(name), fingerprint.size == reference.utf8Count
    else { throw RecoveryError.corruptGenerations }
    let verified = VerifiedBlob(reference: reference, fingerprint: fingerprint)
    if !hydrate, verifiedBlobs[name] == verified { return nil }
    guard let raw = try files.read(name) else { throw RecoveryError.corruptGenerations }
    let text = try reference.decode(raw)
    guard try files.fingerprint(name) == fingerprint else { throw RecoveryError.storageUnavailable }
    verifiedBlobs[name] = verified
    return text
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
