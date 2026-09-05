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
  public var text: String
  public var selection: TextSelection

  public init(
    id: UUID = UUID(), title: String = "Untitled", text: String = "",
    selection: TextSelection = TextSelection()
  ) {
    self.id = id
    self.title = title
    self.text = text
    self.selection = selection
  }
}

public enum WorkspaceValidationError: Error, Equatable, Sendable {
  case emptyWorkspace
  case duplicateTabID
  case missingSelectedTab
  case invalidSelection(UUID)
}

/// Value snapshot passed across the UI/storage concurrency boundary.
public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
  public var revision: UInt64
  public var tabs: [TabSnapshot]
  public var selectedTabID: UUID

  public init(revision: UInt64 = 0, tabs: [TabSnapshot], selectedTabID: UUID) {
    self.revision = revision
    self.tabs = tabs
    self.selectedTabID = selectedTabID
  }

  public static func empty() -> WorkspaceSnapshot {
    let tab = TabSnapshot()
    return WorkspaceSnapshot(tabs: [tab], selectedTabID: tab.id)
  }

  public func validate() throws {
    guard !tabs.isEmpty else { throw WorkspaceValidationError.emptyWorkspace }
    guard Set(tabs.map(\.id)).count == tabs.count else {
      throw WorkspaceValidationError.duplicateTabID
    }
    guard tabs.contains(where: { $0.id == selectedTabID }) else {
      throw WorkspaceValidationError.missingSelectedTab
    }
    for tab in tabs {
      guard tab.selection == tab.selection.clamped(toUTF16Length: tab.text.utf16.count) else {
        throw WorkspaceValidationError.invalidSelection(tab.id)
      }
    }
  }
}
