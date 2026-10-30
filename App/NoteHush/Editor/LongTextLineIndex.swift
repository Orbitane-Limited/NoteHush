import CoreText
import Foundation

struct LongTextIndexedLine: Sendable, Equatable {
  let range: Range<Int>
  let y: CGFloat
  let height: CGFloat
}

struct LongTextLineIndex: Sendable, Equatable {
  let lines: [LongTextIndexedLine]
  let height: CGFloat

  func lineIndex(atUTF16Offset offset: Int) -> Int? {
    guard !lines.isEmpty else { return nil }
    var low = 0
    var high = lines.count
    while low < high {
      let middle = (low + high) / 2
      if lines[middle].range.upperBound <= offset {
        low = middle + 1
      } else {
        high = middle
      }
    }
    return min(low, lines.count - 1)
  }

  func lineIndex(atY y: CGFloat) -> Int? {
    guard !lines.isEmpty else { return nil }
    var low = 0
    var high = lines.count
    while low < high {
      let middle = (low + high) / 2
      if lines[middle].y + lines[middle].height <= y {
        low = middle + 1
      } else {
        high = middle
      }
    }
    return min(low, lines.count - 1)
  }

  func visibleLineRange(atY y: CGFloat, viewportHeight: CGFloat, overscan: Int) -> Range<Int>? {
    guard !lines.isEmpty, height > 0, y.isFinite, viewportHeight.isFinite,
      viewportHeight > 0, overscan >= 0
    else { return nil }
    let top = min(max(0, y), height)
    let bottom = min(height, top + viewportHeight)
    guard let firstVisible = lineIndex(atY: top), let lastVisible = lineIndex(atY: bottom)
    else { return nil }
    let lowerBound = max(0, firstVisible - overscan)
    let upperBound = min(lines.count, lastVisible + overscan + 1)
    return lowerBound..<max(lowerBound + 1, upperBound)
  }

  func textRange(for lineRange: Range<Int>) -> Range<Int>? {
    guard !lineRange.isEmpty, lineRange.lowerBound >= 0,
      lineRange.upperBound <= lines.count
    else { return nil }
    let start = lines[lineRange.lowerBound].range.lowerBound
    let end = lines[lineRange.upperBound - 1].range.upperBound
    return start..<end
  }
}

enum LongTextLineIndexer {
  static func makeIndex(
    text: String, fontName: String, fontSize: CGFloat, textWidth: CGFloat,
    windowSize: Int = 65_536
  ) throws -> LongTextLineIndex {
    let source = text as NSString
    let length = source.length
    guard length > 0 else { return LongTextLineIndex(lines: [], height: 0) }
    guard windowSize > 0, fontSize.isFinite, fontSize > 0, textWidth.isFinite,
      textWidth > 0
    else { throw LongTextLineIndexError.invalidConfiguration }

    let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    let lineHeight = max(
      1,
      CTFontGetAscent(font).rounded()
        + CTFontGetDescent(font).rounded()
        + CTFontGetLeading(font).rounded())
    var spans: [Range<Int>] = []
    var segmentStart = 0

    while segmentStart < length {
      try Task<Never, Never>.checkCancellation()
      let segmentLength = min(windowSize, length - segmentStart)
      let segment = source.substring(with: NSRange(location: segmentStart, length: segmentLength))
      let attributes = [kCTFontAttributeName: font] as CFDictionary
      guard let attributed = CFAttributedStringCreate(nil, segment as CFString, attributes) else {
        throw LongTextLineIndexError.attributedStringCreation
      }
      let typesetter = CTTypesetterCreateWithAttributedString(attributed)
      var localRanges: [Range<Int>] = []
      var localOffset = 0
      while localOffset < segmentLength {
        let suggested = CTTypesetterSuggestLineBreak(typesetter, localOffset, Double(textWidth))
        guard suggested > 0, suggested <= segmentLength - localOffset else {
          throw LongTextLineIndexError.invalidLineBreak
        }
        let lineStart = segmentStart + localOffset
        localRanges.append(lineStart..<(lineStart + suggested))
        localOffset += suggested
      }
      guard !localRanges.isEmpty else { throw LongTextLineIndexError.invalidLineBreak }

      if segmentStart + segmentLength < length, localRanges.count > 1 {
        spans.append(contentsOf: localRanges.dropLast())
        segmentStart = localRanges[localRanges.count - 2].upperBound
      } else {
        spans.append(contentsOf: localRanges)
        segmentStart += segmentLength
      }
    }

    let finalUnit = source.character(at: length - 1)
    if [0x000A, 0x000D, 0x0085, 0x2028, 0x2029].contains(finalUnit) {
      spans.append(length..<length)
    }

    var lines: [LongTextIndexedLine] = []
    lines.reserveCapacity(spans.count)
    var y: CGFloat = 0
    for span in spans {
      lines.append(LongTextIndexedLine(range: span, y: y, height: lineHeight))
      y += lineHeight
    }
    guard lines.first?.range.lowerBound == 0,
      lines.last?.range.upperBound == length,
      zip(lines, lines.dropFirst()).allSatisfy({ $0.range.upperBound == $1.range.lowerBound })
    else { throw LongTextLineIndexError.incompleteCoverage }
    return LongTextLineIndex(lines: lines, height: y)
  }
}

enum LongTextLineIndexError: Error {
  case invalidConfiguration
  case attributedStringCreation
  case invalidLineBreak
  case incompleteCoverage
}
