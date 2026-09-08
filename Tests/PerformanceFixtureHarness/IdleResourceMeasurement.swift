import AppKit
import Darwin
import NoteHushCore

/// Host-only counters for the exact app returned by a generated fixture launch.
/// This type is not linked into any app configuration.
@MainActor
enum IdleResourceMeasurement {
  static let names = ["empty", "fiveMiB"]
  typealias Harness = PerformanceFixtureHarness

  private struct Header: Encodable {
    let record = "header"
    let schema = 1
    let scenario: String
    let api = "proc_pid_rusage/RUSAGE_INFO_V0"
    let clock = "ContinuousClock"
    let cpuUnit = "mach ticks"
    let machTimebaseNumerator: UInt32
    let machTimebaseDenominator: UInt32
    let memoryUnit = "bytes"
    let settlingSeconds = 30
    let plannedIntervals = 60
    let intervalSeconds = 1
  }

  private struct Sample: Encodable {
    let record = "sample"
    let index: Int
    let elapsedBeforeReadNanoseconds: UInt64
    let elapsedAfterReadNanoseconds: UInt64
    let userTimeMachTicks: UInt64
    let systemTimeMachTicks: UInt64
    let residentBytes: UInt64
    let physicalFootprintBytes: UInt64
    let applicationActive: Bool
  }

  private struct Finish: Encodable {
    let record = "finish"
    let normalTermination = true
    let exactFixtureVerification = true
  }

  private enum Failure: String, Error {
    case wrongFixtureSet, wrongProcess, unavailableCounters, changedProcess, inactiveApp
    case evidenceWrite, invalidDuration, changedPresentation
  }

  static func failureCode(for error: Error) -> String? {
    (error as? Failure)?.rawValue
  }

  static func run(_ app: URL, _ manifest: Harness.Manifest, _ manifestURL: URL) async throws {
    guard manifest.fixtures.map(\.name) == names else { throw Failure.wrongFixtureSet }
    var timebase = mach_timebase_info_data_t()
    guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.numer > 0, timebase.denom > 0
    else {
      throw Failure.unavailableCounters
    }
    for fixture in manifest.fixtures {
      try Harness.requireStopped()
      guard
        let before = try await RecoveryStore(directory: Harness.root(fixture.workspace))
          .load().snapshot
      else { throw Harness.Failure.checkpointMissing }
      // Validate the seed before launch without changing its expected revision.
      guard before.revision == fixture.seedRevision,
        before.tabs.map(\.id) == fixture.tabIDs, before.selectedTabID == fixture.selectedTab
      else { throw Harness.Failure.fixtureMismatch }
      let output = manifestURL.deletingLastPathComponent()
        .appending(path: "idle-\(fixture.name).jsonl")
      let descriptor = open(
        output.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
      guard descriptor >= 0 else { throw Failure.evidenceWrite }
      let stream = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      var owned: NSRunningApplication?
      do {
        try append(
          Header(
            scenario: fixture.name, machTimebaseNumerator: timebase.numer,
            machTimebaseDenominator: timebase.denom), to: stream)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.allowsRunningApplicationSubstitution = false
        configuration.environment = ["NOTEHUSH_TEST_WORKSPACE": fixture.workspace.uuidString]
        let process = try await NSWorkspace.shared.openApplication(
          at: app, configuration: configuration)
        guard process.bundleURL?.standardizedFileURL == app,
          process.bundleIdentifier == Harness.bundleID
        else { throw Failure.wrongProcess }
        owned = process
        let clock = ContinuousClock()
        let launched = clock.now
        for second in 1...30 {
          try await clock.sleep(until: launched.advanced(by: .seconds(second)))
          try requireIdentity(process, app)
        }
        // A declared settling interval is not a claim that all deferred work is
        // complete. Any continued CPU activity remains in the observations.
        let started = clock.now
        var startIdentity: UInt64?
        var previousReadEnd: ContinuousClock.Instant?
        for index in 0...60 {
          if let previousReadEnd {
            try await clock.sleep(until: previousReadEnd.advanced(by: .seconds(1)))
          }
          try requireIdentity(process, app)
          let beforeRead = try nanoseconds(started.duration(to: clock.now))
          var usage = rusage_info_v0()
          let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
              proc_pid_rusage(process.processIdentifier, RUSAGE_INFO_V0, $0)
            }
          }
          let readEnded = clock.now
          let afterRead = try nanoseconds(started.duration(to: readEnded))
          previousReadEnd = readEnded
          guard status == 0, usage.ri_proc_start_abstime > 0,
            usage.ri_proc_exit_abstime == 0
          else { throw Failure.unavailableCounters }
          if let startIdentity {
            guard usage.ri_proc_start_abstime == startIdentity else { throw Failure.changedProcess }
          } else {
            startIdentity = usage.ri_proc_start_abstime
          }
          try requireIdentity(process, app)
          let sample = Sample(
            index: index, elapsedBeforeReadNanoseconds: beforeRead,
            elapsedAfterReadNanoseconds: afterRead, userTimeMachTicks: usage.ri_user_time,
            systemTimeMachTicks: usage.ri_system_time, residentBytes: usage.ri_resident_size,
            physicalFootprintBytes: usage.ri_phys_footprint, applicationActive: process.isActive)
          try append(sample, to: stream)
          guard sample.applicationActive else { throw Failure.inactiveApp }
        }
        guard process.terminate() else { throw Harness.Failure.quitFailed }
        try await Harness.wait { process.isTerminated }
        try await Harness.verify(fixture)
        try await verifyPresentation(fixture, before)
        try append(Finish(), to: stream)
        try stream.synchronize()
        try stream.close()
        print("Idle resource observation: \(fixture.name) completed and fixture verified")
      } catch {
        // No cleanup of failed fixture generations or partial evidence. Only the
        // independently identified process from this launch is eligible to stop.
        if let owned, !owned.isTerminated {
          _ = owned.terminate()
          try? await Harness.wait { owned.isTerminated }
          if !owned.isTerminated { owned.forceTerminate() }
        }
        try? stream.synchronize()
        try? stream.close()
        throw error
      }
    }
  }

  private static func requireIdentity(_ process: NSRunningApplication, _ app: URL) throws {
    guard !process.isTerminated, process.bundleURL?.standardizedFileURL == app,
      process.bundleIdentifier == Harness.bundleID
    else { throw Failure.wrongProcess }
  }

  private static func append(_ value: some Encodable, to stream: FileHandle) throws {
    var data = try JSONEncoder().encode(value)
    data.append(0x0A)
    try stream.write(contentsOf: data)
  }

  private static func nanoseconds(_ duration: Duration) throws -> UInt64 {
    let parts = duration.components
    guard parts.seconds >= 0, parts.seconds < 600, parts.attoseconds >= 0 else {
      throw Failure.invalidDuration
    }
    return UInt64(parts.seconds) * 1_000_000_000 + UInt64(parts.attoseconds / 1_000_000_000)
  }

  private static func verifyPresentation(_ fixture: Harness.Fixture, _ before: WorkspaceSnapshot)
    async throws
  {
    guard
      let after = try await RecoveryStore(directory: Harness.root(fixture.workspace))
        .load().snapshot,
      before.tabs.map(\.selection) == after.tabs.map(\.selection),
      (before.preferences ?? EditorPreferences()) == (after.preferences ?? EditorPreferences()),
      (before.closedTabs ?? []).map(\.tab.selection)
        == (after.closedTabs ?? []).map(\.tab.selection)
    else { throw Failure.changedPresentation }
    for (expected, actual) in zip(before.tabs, after.tabs) {
      guard let original = expected.scroll, let recovered = actual.scroll,
        original.anchor == recovered.anchor, abs(original.offset - recovered.offset) <= 1,
        abs((original.horizontalOffset ?? 0) - (recovered.horizontalOffset ?? 0)) <= 1
      else { throw Failure.changedPresentation }
    }
  }
}
