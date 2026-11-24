import AppKit
import CoreText

@main
@MainActor
enum CoreTextLongProbe {
  static func main() throws {
    guard CommandLine.arguments.count == 3, let bytes = Int(CommandLine.arguments[1]),
      bytes > 0, bytes <= 1_048_576, bytes.isMultiple(of: 8),
      ["native", "rtl", "noLigatures", "forcedRTL", "bounded"].contains(CommandLine.arguments[2])
    else { exit(64) }
    let variant = CommandLine.arguments[2]
    let text = String(repeating: "خط📝", count: bytes / 8)
    let style = NSMutableParagraphStyle()
    if variant == "rtl" { style.baseWritingDirection = .rightToLeft }
    var attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .paragraphStyle: style,
    ]
    if variant == "noLigatures" { attributes[.ligature] = 0 }
    let attributed = NSAttributedString(string: text, attributes: attributes)
    var options: [String: Any] = [kCTTypesetterOptionAllowUnboundedLayout as String: variant != "bounded"]
    if variant == "forcedRTL" { options[kCTTypesetterOptionForcedEmbeddingLevel as String] = 1 }
    let begin: [String: Any] = ["kind": "begin", "bytes": bytes, "utf16": attributed.length, "variant": variant]
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: begin) + Data([10]))
    let clock = ContinuousClock()
    let started = clock.now
    let typesetter = CTTypesetterCreateWithAttributedStringAndOptions(attributed, options as CFDictionary)
    let elapsed = started.duration(to: clock.now).components
    let result: [String: Any] = [
      "kind": "result", "bytes": bytes, "variant": variant, "createdTypesetter": typesetter != nil,
      "nanoseconds": elapsed.seconds * 1_000_000_000 + elapsed.attoseconds / 1_000_000_000,
    ]
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result) + Data([10]))
    withExtendedLifetime(typesetter) {}
  }
}
