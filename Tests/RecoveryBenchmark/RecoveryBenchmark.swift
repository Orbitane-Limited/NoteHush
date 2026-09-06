import Foundation
import NoteHushCore
import os

/// Generated data only. Wall time and I/O counters describe the recovery store,
/// not first-frame launch, editor latency, physical disk traffic or energy.
@main
enum RecoveryBenchmark {
  struct Counters: Encodable, Sendable {
    var bytesRead = 0
    var bytesWritten = 0
    var writes = 0
  }

  struct Distribution: Encodable {
    let median: Double
    let p95: Double
    let samples: [Double]

    init(_ values: [Double]) {
      let sorted = values.sorted()
      median = (sorted[9] + sorted[10]) / 2
      p95 = sorted[18]
      samples = values
    }
  }

  struct Measurement: Encodable {
    let operation: String
    let milliseconds: Distribution
    let bytesRead: Distribution
    let bytesWritten: Distribution
    let writes: Distribution
  }

  struct Scenario: Encodable {
    let openTabs: Int
    let closedTabs: Int
    let bytesPerTab: Int
    let samples: Int
    let measurements: [Measurement]
  }

  struct Report: Encodable {
    let schema = 1
    let measuredAt = Date().ISO8601Format()
    let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    let logicalProcessors = ProcessInfo.processInfo.processorCount
    let physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory
    let cacheCondition = "warm filesystem cache; new store for each restore; no debugger"
    let textDistribution =
      "unique tab prefixes; alternating ASCII and Arabic/combining-mark/emoji text, all with CRLF"
    let scenarios: [Scenario]
  }

  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "NoteHushRecoveryBenchmark-\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    var scenarios: [Scenario] = []
    for (open, closed) in [(20, 0), (100, 20)] {
      scenarios.append(try await measure(open: open, closed: closed, root: root))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(Report(scenarios: scenarios)))
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  static func measure(open: Int, closed: Int, root: URL) async throws -> Scenario {
    let byteCount = 256 * 1024
    let tails = ["generated line\r\n", "خط e\u{301} 📝.\r\n"].map {
      String(repeating: $0, count: byteCount / 16 - 1)
    }
    func tab(_ index: Int) -> TabSnapshot {
      let text = String(format: "tab-%010d\r\n", index) + tails[index % tails.count]
      precondition(text.utf8.count == byteCount)
      return TabSnapshot(text: text)
    }
    let tabs = (0..<open).map(tab)
    let history = (0..<closed).map {
      ClosedTabSnapshot(tab: tab(open + $0), originalIndex: $0)
    }
    var snapshot = WorkspaceSnapshot(
      revision: 1, tabs: tabs, selectedTabID: tabs[0].id, closedTabs: history)
    let counters = OSAllocatedUnfairLock(initialState: Counters())
    let files = CountingFiles(
      base: DiskRecoveryFiles(directory: root.appending(path: "tabs-\(open)")),
      counters: counters)
    let store = RecoveryStore(files: files)
    try await store.commit(snapshot)
    var results: [Measurement] = []
    for operation in ["restore", "selection-only", "one-tab-edit"] {
      var timings: [Double] = []
      var reads: [Double] = []
      var writes: [Double] = []
      var counts: [Double] = []
      for sample in 0..<20 {
        if operation != "restore" {
          snapshot.revision += 1
          snapshot.tabs[0].selection = TextSelection(location: sample + 1)
          if operation == "one-tab-edit" { snapshot.tabs[sample % 2].text += "x" }
        }
        counters.withLock { $0 = Counters() }
        let start = ContinuousClock.now
        let restored: WorkspaceSnapshot?
        if operation == "restore" {
          let loaded = try await RecoveryStore(files: files).load()
          restored = loaded.snapshot
        } else {
          try await store.commit(snapshot)
          restored = nil
        }
        let duration = start.duration(to: .now).components
        timings.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
        let count = counters.withLock { $0 }
        reads.append(Double(count.bytesRead))
        writes.append(Double(count.bytesWritten))
        counts.append(Double(count.writes))
        if operation == "restore" {
          try verify(restored, expected: snapshot)
        } else {
          try verify(try await RecoveryStore(files: files).load().snapshot, expected: snapshot)
        }
      }
      results.append(
        Measurement(
          operation: operation, milliseconds: Distribution(timings), bytesRead: Distribution(reads),
          bytesWritten: Distribution(writes), writes: Distribution(counts)))
    }
    return Scenario(
      openTabs: open, closedTabs: closed, bytesPerTab: byteCount, samples: 20,
      measurements: results)
  }

  enum Failure: Error { case incorrectRecovery }

  /// Compare encoded bytes as well as state; Swift String equality alone treats
  /// canonically equivalent Unicode sequences as equal. Verification is untimed.
  static func verify(_ actual: WorkspaceSnapshot?, expected: WorkspaceSnapshot) throws {
    guard let actual else { throw Failure.incorrectRecovery }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard try encoder.encode(actual) == encoder.encode(expected) else {
      throw Failure.incorrectRecovery
    }
  }

  struct CountingFiles: RecoveryFiles {
    let base: DiskRecoveryFiles
    let counters: OSAllocatedUnfairLock<Counters>

    func read(_ name: String) throws -> Data? {
      let data = try base.read(name)
      counters.withLock { $0.bytesRead += data?.count ?? 0 }
      return data
    }

    func writeAtomically(_ data: Data, named name: String) throws {
      try base.writeAtomically(data, named: name)
      counters.withLock {
        $0.bytesWritten += data.count
        $0.writes += 1
      }
    }

    func synchronizeDirectory() throws { try base.synchronizeDirectory() }

    func withExclusiveAccess<T>(_ operation: () throws -> T) throws -> T {
      try base.withExclusiveAccess(operation)
    }
  }
}
