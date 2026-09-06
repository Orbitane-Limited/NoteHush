import Foundation

public struct ResolvedFileBookmark: Sendable {
  public let url: URL
  public let isStale: Bool

  public init(url: URL, isStale: Bool) {
    self.url = url
    self.isStale = isStale
  }
}

/// Injected to exercise revoked access, stale bookmarks and balanced scopes.
public protocol FileBookmarking: Sendable {
  func create(for url: URL) throws -> Data
  func resolve(_ data: Data) throws -> ResolvedFileBookmark
  func startAccessing(_ url: URL) -> Bool
  func stopAccessing(_ url: URL)
}

public struct SecurityScopedFileBookmarks: FileBookmarking {
  public init() {}

  public func create(for url: URL) throws -> Data {
    try url.bookmarkData(
      options: .withSecurityScope, includingResourceValuesForKeys: nil,
      relativeTo: nil)
  }

  public func resolve(_ data: Data) throws -> ResolvedFileBookmark {
    var stale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope, .withoutUI, .withoutMounting],
      relativeTo: nil, bookmarkDataIsStale: &stale)
    return ResolvedFileBookmark(url: url, isStale: stale)
  }

  public func startAccessing(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
  public func stopAccessing(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}
