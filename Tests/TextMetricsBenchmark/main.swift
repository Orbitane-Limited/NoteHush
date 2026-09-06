import Foundation
import NoteHushCore

// Informational optimized microbenchmark, never a substitute for end-to-end
// launch/typing/restore profiling. All inputs are generated fixtures.
@main
struct TextMetricsBenchmark {
  static func main() throws {
    let cases: [(name: String, bytes: Int, unit: String)] = [
      ("1KiB mixed", 1024, "abc 👩🏽‍💻 اردو e\u{301}\r\n"),
      ("1MiB mixed", 1024 * 1024, "abc 👩🏽‍💻 اردو e\u{301}\r\n"),
      ("10MiB mixed", 10 * 1024 * 1024, "abc 👩🏽‍💻 اردو e\u{301}\r\n"),
      ("10MiB single line", 10 * 1024 * 1024, "x"),
      ("100MiB ASCII", 100 * 1024 * 1024, "abcdefghijklmno\n"),
    ]
    var checksum = 0
    print(
      "20 repetitions; index build ms median/p95; batch of 1000 caret+selection+line queries ms median/p95"
    )
    for fixture in cases {
      let text = String(repeating: fixture.unit, count: fixture.bytes / fixture.unit.utf8.count)
      var builds: [Double] = []
      var queries: [Double] = []
      for _ in 0..<20 {
        let start = ContinuousClock.now
        let metrics = try TextMetrics(text)
        builds.append(milliseconds(start.duration(to: .now)))
        let queryStart = ContinuousClock.now
        for index in 0..<1000 {
          let offset = (index * 104729) % (metrics.utf16Count + 1)
          let position = metrics.position(atUTF16Offset: offset)
          checksum &+= position.column
          checksum &+= metrics.selectedCharacterCount(
            in: TextSelection(location: offset, length: 37))
          checksum &+= metrics.utf16Offset(forLine: position.line) ?? 0
        }
        queries.append(milliseconds(queryStart.duration(to: .now)))
      }
      print(
        "\(fixture.name), bytes=\(text.utf8.count): build \(summary(builds)); queries \(summary(queries))"
      )
    }
    print("checksum=\(checksum)")
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
  }

  private static func summary(_ values: [Double]) -> String {
    let sorted = values.sorted()
    return String(format: "%.3f/%.3f", (sorted[9] + sorted[10]) / 2, sorted[18])
  }
}
