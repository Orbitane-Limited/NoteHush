import AppKit
import CoreFoundation
import Foundation

let byteCount = 10 * 1024 * 1024
let header = "123456789012345\n"
let unit = "خط📝"
let text = header + String(repeating: unit, count: (byteCount - header.utf8.count) / 8)
let style = NSMutableParagraphStyle()
style.baseWritingDirection = .natural
let source = NSAttributedString(
  string: text,
  attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
    .paragraphStyle: style,
  ])
var levels = [UInt8](repeating: 253, count: source.length)
var directions = [UInt8](repeating: 253, count: source.length)
let clock = ContinuousClock()
let started = clock.now
let classified = levels.withUnsafeMutableBufferPointer { levelBuffer in
  directions.withUnsafeMutableBufferPointer { directionBuffer in
    CFAttributedStringGetStatisticalWritingDirections(
      source as CFAttributedString,
      CFRange(location: 0, length: source.length), -1,
      levelBuffer.baseAddress, directionBuffer.baseAddress)
  }
}
let elapsed = started.duration(to: clock.now)
let distinct = Set(directions)
let parts = elapsed.components
let elapsedNanoseconds = UInt64(parts.seconds) * 1_000_000_000
  + UInt64(parts.attoseconds / 1_000_000_000)
print("utf8=\(text.utf8.count) utf16=\(source.length) classified=\(classified) elapsed_ns=\(elapsedNanoseconds) distinct_directions=\(distinct.sorted()) all_same=\(distinct.count == 1)")
