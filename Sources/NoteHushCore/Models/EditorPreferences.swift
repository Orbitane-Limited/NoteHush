import Foundation

/// Presentation only. No document text, file paths or system-wide defaults.
public struct EditorPreferences: Codable, Equatable, Sendable {
  public enum Appearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark
  }

  /// PostScript name preserves the chosen face; nil follows the system monospace font.
  public var fontName: String?
  public var fontSize: Double = 14
  public var zoomPercent: Int = 100
  public var appearance: Appearance = .system
  public var wordWrap: Bool = true
  public var checksSpelling: Bool = false

  public static let zoomSteps = [50, 75, 90, 100, 110, 125, 150, 175, 200, 250, 300]

  public init() {}

  public var normalized: Self {
    var result = self
    if let fontName, fontName.isEmpty || fontName.utf8.count > 256 { result.fontName = nil }
    result.fontSize = fontSize.isFinite ? min(72, max(8, fontSize)) : 14
    result.zoomPercent = min(300, max(50, zoomPercent))
    return result
  }

  public func zoomed(increasing: Bool) -> Self {
    var result = normalized
    result.zoomPercent =
      increasing
      ? Self.zoomSteps.first(where: { $0 > result.zoomPercent }) ?? 300
      : Self.zoomSteps.last(where: { $0 < result.zoomPercent }) ?? 50
    return result
  }
}
