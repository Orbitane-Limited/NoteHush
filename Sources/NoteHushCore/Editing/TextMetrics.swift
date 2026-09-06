import Foundation

public enum TextNewline: String, CaseIterable, Sendable {
  case crlf = "CRLF"
  case lf = "LF"
  case cr = "CR"
  case nel = "NEL"
  case lineSeparator = "LS"
  case
    paragraphSeparator = "PS"
}

public struct TextPosition: Equatable, Sendable {
  public let line: Int
  public let column: Int
}

/// Immutable, sparse index. Counts are extended grapheme clusters; selection and
/// navigation offsets remain UTF-16 to match AppKit. CRLF is one line break.
public struct TextMetrics: Sendable {
  private struct Checkpoint: Sendable {
    var index: String.Index
    var utf16Offset = 0
    var characters = 0
    var line = 1
    var lineStartCharacters = 0
    var lineStartUTF16 = 0
  }

  public static let empty = TextMetrics()
  public let characterCount: Int
  public let utf16Count: Int
  public let lineCount: Int
  public let newlineKinds: Set<TextNewline>
  private let text: String
  private let checkpoints: [Checkpoint]

  private init() {
    text = ""
    checkpoints = [Checkpoint(index: text.startIndex)]
    characterCount = 0
    utf16Count = 0
    lineCount = 1
    newlineKinds = []
  }

  public init(_ text: String) throws {
    self.text = text
    var state = Checkpoint(index: text.startIndex)
    var points = [state]
    var kinds: Set<TextNewline> = []
    while state.index < text.endIndex {
      if state.characters.isMultiple(of: 512) { try Task.checkCancellation() }
      let next = text.index(after: state.index)
      let length = text.utf16.distance(from: state.index, to: next)
      // Index both sides of unusually large clusters so main-thread queries
      // never have to walk a megabyte-long combining sequence.
      if length > 256, points.last?.utf16Offset != state.utf16Offset { points.append(state) }
      let newline = Self.newline(in: text, at: state.index, length: length)
      if let newline { kinds.insert(newline) }
      Self.advance(&state, to: next, length: length, newline: newline != nil)
      if state.characters.isMultiple(of: 512) || length > 256 { points.append(state) }
    }
    try Task.checkCancellation()
    if points.last?.utf16Offset != state.utf16Offset { points.append(state) }
    checkpoints = points
    characterCount = state.characters
    utf16Count = state.utf16Offset
    lineCount = state.line
    newlineKinds = kinds
  }

  public func position(atUTF16Offset offset: Int) -> TextPosition {
    let point = boundary(at: offset).floor
    return TextPosition(line: point.line, column: point.characters - point.lineStartCharacters + 1)
  }

  /// Count graphemes touched by a nonempty selection, including partial UTF-16
  /// ranges restored from older state. A caret itself selects zero characters.
  public func selectedCharacterCount(in selection: TextSelection) -> Int {
    let range = selection.clamped(toUTF16Length: utf16Count)
    guard range.length > 0 else { return 0 }
    let start = boundary(at: range.location)
    let end = boundary(at: range.location + range.length)
    return end.floor.characters + (end.insideCharacter ? 1 : 0) - start.floor.characters
  }

  public func utf16Offset(forLine line: Int) -> Int? {
    guard line >= 1, line <= lineCount else { return nil }
    var point = checkpoints[lastCheckpoint { $0.line <= line }]
    while point.line < line {
      let next = text.index(after: point.index)
      let length = text.utf16.distance(from: point.index, to: next)
      Self.advance(
        &point, to: next, length: length,
        newline: Self.newline(in: text, at: point.index, length: length) != nil)
    }
    return point.lineStartUTF16
  }

  private func boundary(at offset: Int) -> (floor: Checkpoint, insideCharacter: Bool) {
    let target = min(max(offset, 0), utf16Count)
    let checkpoint = lastCheckpoint { $0.utf16Offset <= target }
    var point = checkpoints[checkpoint]
    if checkpoint + 1 < checkpoints.count,
      checkpoints[checkpoint + 1].characters == point.characters + 1,
      target < checkpoints[checkpoint + 1].utf16Offset
    {
      return (point, target > point.utf16Offset)
    }
    while point.utf16Offset < target {
      let next = text.index(after: point.index)
      let length = text.utf16.distance(from: point.index, to: next)
      if point.utf16Offset + length > target { return (point, true) }
      Self.advance(
        &point, to: next, length: length,
        newline: Self.newline(in: text, at: point.index, length: length) != nil)
    }
    return (point, false)
  }

  private func lastCheckpoint(where predicate: (Checkpoint) -> Bool) -> Int {
    var lower = 0
    var upper = checkpoints.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if predicate(checkpoints[middle]) { lower = middle + 1 } else { upper = middle }
    }
    return max(0, lower - 1)
  }

  private static func advance(
    _ point: inout Checkpoint, to index: String.Index, length: Int,
    newline: Bool
  ) {
    point.index = index
    point.utf16Offset += length
    point.characters += 1
    if newline {
      point.line += 1
      point.lineStartCharacters = point.characters
      point.lineStartUTF16 = point.utf16Offset
    }
  }

  private static func newline(in text: String, at index: String.Index, length: Int) -> TextNewline?
  {
    guard length <= 2 else { return nil }
    // Scalar checks avoid repeated canonical-equivalence comparisons against
    // newline Characters for every ordinary character in a Unicode document.
    switch text.unicodeScalars[index].value {
    case 0x0D: return length == 2 ? .crlf : .cr
    case 0x0A: return .lf
    case 0x85: return .nel
    case 0x2028: return .lineSeparator
    case 0x2029: return .paragraphSeparator
    default: return nil
    }
  }
}

/// A cancellation boundary also used to inject late results in AppKit tests.
public protocol TextAnalyzing: Sendable {
  func analyze(_ text: String) async throws -> TextMetrics
}

public struct BackgroundTextAnalyzer: TextAnalyzing {
  public init() {}
  public func analyze(_ text: String) async throws -> TextMetrics {
    let worker = Task.detached(priority: .utility) { try TextMetrics(text) }
    return try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: {
      worker.cancel()
    }
  }
}
