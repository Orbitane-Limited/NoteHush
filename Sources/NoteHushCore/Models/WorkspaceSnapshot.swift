import Foundation

/// AppKit positions are UTF-16 offsets, including for emoji and combining marks.
public struct TextSelection: Codable, Equatable, Sendable {
  public var location: Int
  public var length: Int

  public init(location: Int = 0, length: Int = 0) {
    self.location = location
    self.length = length
  }

  public func clamped(toUTF16Length count: Int) -> TextSelection {
    let limit = max(0, count)
    let start = min(max(0, location), limit)
    return TextSelection(location: start, length: min(max(0, length), limit - start))
  }
}

public struct TabSnapshot: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public var title: String
  private var capturedText: CapturedText
  public var text: String {
    get { capturedText.value }
    set { capturedText = CapturedText(value: newValue) }
  }
  // An in-memory identity, never decoded from disk or accepted from a caller.
  // Copies share it until an assignment creates a new immutable text value.
  var textIdentity: UUID { capturedText.identity }
  public var selection: TextSelection
  public var scroll: TextScrollPosition?
  public var file: FileBinding?

  public init(
    id: UUID = UUID(), title: String = "Untitled", text: String = "",
    selection: TextSelection = TextSelection(), scroll: TextScrollPosition? = nil,
    file: FileBinding? = nil
  ) {
    self.id = id
    self.title = title
    capturedText = CapturedText(value: text)
    self.selection = selection
    self.scroll = scroll
    self.file = file
  }

  private struct CapturedText: Equatable, Sendable {
    let value: String
    let identity = UUID()

    static func == (left: Self, right: Self) -> Bool { left.value == right.value }
  }

  // Keep the original flat Codable shape for legacy recovery, exports and
  // independent crash-test oracles. The transient identity is not persistence.
  private enum CodingKeys: String, CodingKey { case id, title, text, selection, scroll, file }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try values.decode(UUID.self, forKey: .id),
      title: try values.decode(String.self, forKey: .title),
      text: try values.decode(String.self, forKey: .text),
      selection: try values.decode(TextSelection.self, forKey: .selection),
      scroll: try values.decodeIfPresent(TextScrollPosition.self, forKey: .scroll),
      file: try values.decodeIfPresent(FileBinding.self, forKey: .file))
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(title, forKey: .title)
    try values.encode(text, forKey: .text)
    try values.encode(selection, forKey: .selection)
    try values.encodeIfPresent(scroll, forKey: .scroll)
    try values.encodeIfPresent(file, forKey: .file)
  }
}

/// A UTF-16 text anchor and displacement within its line, independent of window size.
public struct TextScrollPosition: Codable, Equatable, Sendable {
  public var anchor: Int
  public var offset: Double
  public var horizontalOffset: Double?

  public init(anchor: Int, offset: Double, horizontalOffset: Double? = nil) {
    self.anchor = anchor
    self.offset = offset
    self.horizontalOffset = horizontalOffset
  }
}

public struct WindowFrame: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public var isValid: Bool {
    x.isFinite && y.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0
  }
}

public enum WorkspaceValidationError: Error, Equatable, Sendable {
  case emptyWorkspace
  case duplicateTabID
  case missingSelectedTab
  case invalidSelection(UUID)
  case invalidClosedTabs
}

/// Newest first. Store values, not live text systems or undo stacks.
public struct ClosedTabSnapshot: Codable, Equatable, Sendable {
  public static let limit = 20
  public var tab: TabSnapshot
  public var originalIndex: Int

  public init(tab: TabSnapshot, originalIndex: Int) {
    self.tab = tab
    self.originalIndex = originalIndex
  }
}

/// Value snapshot passed across the UI/storage concurrency boundary.
public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
  public var revision: UInt64
  public var tabs: [TabSnapshot]
  public var selectedTabID: UUID
  // Optional additions keep schema-1 snapshots written before UI integration readable.
  public var windowFrame: WindowFrame?
  public var preferences: EditorPreferences?
  public var closedTabs: [ClosedTabSnapshot]?

  public init(
    revision: UInt64 = 0, tabs: [TabSnapshot], selectedTabID: UUID,
    windowFrame: WindowFrame? = nil, preferences: EditorPreferences? = nil,
    closedTabs: [ClosedTabSnapshot]? = nil
  ) {
    self.revision = revision
    self.tabs = tabs
    self.selectedTabID = selectedTabID
    self.windowFrame = windowFrame
    self.preferences = preferences
    self.closedTabs = closedTabs
  }

  public static func empty() -> WorkspaceSnapshot {
    let tab = TabSnapshot()
    return WorkspaceSnapshot(tabs: [tab], selectedTabID: tab.id)
  }

  public func validate() throws {
    try validate(utf16Length: { $0.text.utf16.count })
  }

  /// Recovery may reuse a length computed from the same immutable text identity.
  /// The public validator still derives every bound directly from its text.
  func validate(utf16Length: (TabSnapshot) throws -> Int) throws {
    guard !tabs.isEmpty else { throw WorkspaceValidationError.emptyWorkspace }
    guard Set(tabs.map(\.id)).count == tabs.count else {
      throw WorkspaceValidationError.duplicateTabID
    }
    guard tabs.contains(where: { $0.id == selectedTabID }) else {
      throw WorkspaceValidationError.missingSelectedTab
    }
    let closed = closedTabs ?? []
    let allTabs = tabs + closed.map(\.tab)
    guard closed.count <= ClosedTabSnapshot.limit,
      closed.allSatisfy({ $0.originalIndex >= 0 }),
      Set(allTabs.map(\.id)).count == allTabs.count
    else { throw WorkspaceValidationError.invalidClosedTabs }
    for tab in allTabs {
      let count = try utf16Length(tab)
      guard count >= 0, tab.selection == tab.selection.clamped(toUTF16Length: count) else {
        throw WorkspaceValidationError.invalidSelection(tab.id)
      }
    }
  }
}
