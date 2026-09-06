import AppKit
import NoteHushCore

extension EditorPreferences {
  @MainActor
  func font(zoomed: Bool = true) -> NSFont {
    let value = normalized
    let size = value.fontSize * (zoomed ? Double(value.zoomPercent) / 100 : 1)
    return value.fontName.flatMap { NSFont(name: $0, size: size) }
      ?? .monospacedSystemFont(ofSize: size, weight: .regular)
  }

  @MainActor
  var appKitAppearance: NSAppearance? {
    switch appearance {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }
}
