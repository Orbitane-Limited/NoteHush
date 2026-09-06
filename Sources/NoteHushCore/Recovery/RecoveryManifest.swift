import CryptoKit
import Foundation

/// Immutable references derive filenames from a UUID and a validated digest;
/// recovery never accepts a path from manifest content.
struct RecoveryBlobReference: Codable, Equatable, Sendable {
  static let maximumBytes = 256 * 1024 * 1024
  let sha256: String
  let utf8Count: Int
  let utf16Count: Int

  init(text: String) throws {
    let byteCount = text.utf8.count
    guard byteCount <= Self.maximumBytes else { throw RecoveryError.snapshotTooLarge }
    try self.init(
      sha256: Self.digest(Data(text.utf8)), utf8Count: byteCount, utf16Count: text.utf16.count)
  }

  init(sha256: String, utf8Count: Int, utf16Count: Int) throws {
    guard sha256.utf8.count == 64,
      sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
      (0...Self.maximumBytes).contains(utf8Count), (0...utf8Count).contains(utf16Count)
    else { throw RecoveryError.corruptGenerations }
    self.sha256 = sha256
    self.utf8Count = utf8Count
    self.utf16Count = utf16Count
  }

  private enum CodingKeys: String, CodingKey { case sha256, utf8Count, utf16Count }

  init(from decoder: any Decoder) throws {
    let fields = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      sha256: fields.decode(String.self, forKey: .sha256),
      utf8Count: fields.decode(Int.self, forKey: .utf8Count),
      utf16Count: fields.decode(Int.self, forKey: .utf16Count))
  }

  func name(for tabID: UUID) -> String { "blob-\(tabID.uuidString)-\(sha256).utf8" }

  static func isManagedName(_ name: String) -> Bool {
    guard name.utf8.count == 111, name.hasPrefix("blob-"), name.hasSuffix(".utf8") else {
      return false
    }
    let identifier = String(name.dropFirst(5).prefix(36))
    guard let id = UUID(uuidString: identifier), id.uuidString == identifier,
      name.dropFirst(41).first == "-"
    else { return false }
    return (try? Self(sha256: String(name.dropFirst(42).prefix(64)), utf8Count: 0, utf16Count: 0))
      != nil
  }

  func decode(_ data: Data) throws -> String {
    guard data.count == utf8Count, Self.digest(data) == sha256 else {
      throw RecoveryError.corruptGenerations
    }
    // Foundation's encoding initializer consumes a leading BOM. Here U+FEFF
    // is document content; strict round-trip validation also rejects repaired UTF-8.
    let text = String(decoding: data, as: UTF8.self)
    guard text.utf8.elementsEqual(data), text.utf16.count == utf16Count
    else { throw RecoveryError.corruptGenerations }
    return text
  }

  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

struct RecoveryManifest: Codable, Sendable {
  // This replaces the former 256 MiB encoded-envelope capacity with a bounded
  // raw text budget. Never allocate the sum of unvalidated blob declarations.
  static let maximumTextBytes = 256 * 1024 * 1024

  struct Tab: Codable, Sendable {
    let id: UUID
    let title: String
    let content: RecoveryBlobReference
    let selection: TextSelection
    let scroll: TextScrollPosition?
    let file: FileBinding?
  }

  struct ClosedTab: Codable, Sendable {
    let tab: Tab
    let originalIndex: Int
  }

  let revision: UInt64
  let tabs: [Tab]
  let selectedTabID: UUID
  let windowFrame: WindowFrame?
  let preferences: EditorPreferences?
  let closedTabs: [ClosedTab]?

  var allTabs: [Tab] { tabs + (closedTabs ?? []).map(\.tab) }
  var blobNames: Set<String> { Set(allTabs.map { $0.content.name(for: $0.id) }) }
  var tabIDs: Set<UUID> { Set(allTabs.map(\.id)) }

  init(
    snapshot: WorkspaceSnapshot,
    reference: (TabSnapshot) throws -> RecoveryBlobReference
  ) rethrows {
    func tab(_ value: TabSnapshot) throws -> Tab {
      Tab(
        id: value.id, title: value.title, content: try reference(value),
        selection: value.selection, scroll: value.scroll, file: value.file)
    }
    revision = snapshot.revision
    tabs = try snapshot.tabs.map(tab)
    selectedTabID = snapshot.selectedTabID
    windowFrame = snapshot.windowFrame
    preferences = snapshot.preferences
    closedTabs = try snapshot.closedTabs?.map {
      ClosedTab(tab: try tab($0.tab), originalIndex: $0.originalIndex)
    }
  }

  /// Check structure/declared bounds before reading blobs. The blob reader must
  /// additionally verify these lengths against checksummed, strictly decoded text.
  func validate() throws {
    var bytes = 0
    var lengths: [UUID: Int] = [:]
    for tab in allTabs {
      guard bytes <= Self.maximumTextBytes - tab.content.utf8Count else {
        throw RecoveryError.snapshotTooLarge
      }
      bytes += tab.content.utf8Count
      // Do not use Dictionary(uniqueKeysWithValues:): duplicate IDs must throw,
      // not trap, when the shared workspace validator examines the metadata.
      lengths[tab.id] = tab.content.utf16Count
    }
    let metadata = snapshot { _, _ in "" }
    try metadata.validate { tab in
      guard let length = lengths[tab.id] else { throw RecoveryError.corruptGenerations }
      return length
    }
  }

  func snapshot(resolve: (UUID, RecoveryBlobReference) throws -> String) rethrows
    -> WorkspaceSnapshot
  {
    func tab(_ value: Tab) throws -> TabSnapshot {
      TabSnapshot(
        id: value.id, title: value.title, text: try resolve(value.id, value.content),
        selection: value.selection, scroll: value.scroll, file: value.file)
    }
    return WorkspaceSnapshot(
      revision: revision, tabs: try tabs.map(tab), selectedTabID: selectedTabID,
      windowFrame: windowFrame, preferences: preferences,
      closedTabs: try closedTabs?.map {
        ClosedTabSnapshot(tab: try tab($0.tab), originalIndex: $0.originalIndex)
      })
  }
}
