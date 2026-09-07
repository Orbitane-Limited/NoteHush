import AppKit
import CryptoKit
import NoteHushCore

/// Host-only fixture ownership. The sandboxed XCTest runner cannot write another
/// app's container. This executable is never linked into the shipping app.
@main
@MainActor
enum PerformanceFixtureHarness {
  static let bundleID = "pk.codehub.NoteHush.PerformanceTesting"
  static let names = ["empty", "fiveMiB", "thirtyMiB"]

  struct Fixture: Codable {
    let name: String
    let workspace: UUID
    let selectedTab: UUID
    let tabIDs: [UUID]
    let tabDigests: [Data]
    let closedIDs: [UUID]
    let closedDigests: [Data]
    let seedRevision: UInt64
  }
  struct Manifest: Codable {
    let version: Int
    let applicationURL: URL
    let fixtures: [Fixture]
    let environment: Environment
  }
  struct Environment: Codable {
    let capturedAt: Date
    let lowPowerMode: Bool
    let thermalState: Int
    let screens: [Screen]
  }
  struct Screen: Codable {
    let widthPoints: Double
    let heightPoints: Double
    let scale: Double
  }
  enum Failure: Error {
    case arguments, wrongBuild, appRunning, wrongManifest, missingGuard
    case launchFailed, checkpointMissing, quitFailed, fixtureMismatch
    case profilerTimedOut, profilerTraceMissing
    case profilerRecorderFailed(Int32)
  }

  static func main() async {
    do {
      guard CommandLine.arguments.count == 4,
        ["prepare", "verify", "cleanup", "profile"].contains(CommandLine.arguments[1])
      else { throw Failure.arguments }
      let command = CommandLine.arguments[1]
      let app = URL(filePath: CommandLine.arguments[2], directoryHint: .isDirectory)
        .standardizedFileURL
      let manifestURL = URL(filePath: CommandLine.arguments[3])
      guard let bundle = Bundle(url: app), bundle.bundleIdentifier == bundleID,
        bundle.object(forInfoDictionaryKey: "NoteHushRequiresTestWorkspace") as? String == "YES",
        bundle.object(forInfoDictionaryKey: "NoteHushPerformanceBuild") as? String == "YES",
        bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
          == "NoteHushPerformance"
      else { throw Failure.wrongBuild }
      try requireStopped()
      if command == "prepare" {
        guard !FileManager.default.fileExists(atPath: manifestURL.path) else {
          throw Failure.wrongManifest
        }
        try await prepare(app, manifestURL)
      } else {
        let manifest = try JSONDecoder().decode(
          Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.version == 1, manifest.applicationURL == app,
          manifest.fixtures.map(\.name) == names,
          Set(manifest.fixtures.map(\.workspace)).count == names.count
        else { throw Failure.wrongManifest }
        if command == "profile" {
          try await profile(app, manifest, manifestURL)
        } else if command == "verify" {
          for fixture in manifest.fixtures { try await verify(fixture) }
        } else {
          for fixture in manifest.fixtures { try remove(fixture.workspace) }
          try FileManager.default.removeItem(at: manifestURL)
        }
      }
      print("Performance fixtures: \(command) passed")
    } catch {
      let reason = (error as? Failure).map { String(describing: $0) } ?? "fixtureOperationFailed"
      FileHandle.standardError.write(Data("Performance fixtures failed: \(reason)\n".utf8))
      exit(1)
    }
  }

  private static func profile(_ app: URL, _ manifest: Manifest, _ manifestURL: URL) async throws {
    guard let fixture = manifest.fixtures.first(where: { $0.name == "fiveMiB" }) else {
      throw Failure.wrongManifest
    }
    let logs = manifestURL.deletingLastPathComponent().appending(path: "logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    let trace = logs.appending(path: "PerformanceAttached-\(UUID().uuidString).trace")
    let recorder = Process()
    recorder.executableURL = URL(filePath: "/usr/bin/xcrun")
    var owned: NSRunningApplication?
    do {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.allowsRunningApplicationSubstitution = false
      configuration.environment = ["NOTEHUSH_TEST_WORKSPACE": fixture.workspace.uuidString]
      let process = try await NSWorkspace.shared.openApplication(
        at: app, configuration: configuration)
      guard process.bundleURL?.standardizedFileURL == app, process.bundleIdentifier == bundleID
      else {
        throw Failure.wrongBuild
      }
      owned = process
      // Attach only to the PID returned for this verified, generated-workspace
      // launch. This trace begins after LaunchServices startup; it is not the
      // unprofiled process-entry/readiness measurement.
      recorder.arguments = [
        "xctrace", "record", "--template", "Time Profiler", "--time-limit", "10s",
        "--output", trace.path, "--attach", String(process.processIdentifier),
      ]
      try recorder.run()
      let clock = ContinuousClock()
      let deadline = clock.now.advanced(by: .seconds(45))
      while recorder.isRunning {
        guard !process.isTerminated else { throw Failure.quitFailed }
        guard clock.now < deadline else { throw Failure.profilerTimedOut }
        try await clock.sleep(until: clock.now.advanced(by: .milliseconds(20)))
      }
      guard recorder.terminationReason == .exit, recorder.terminationStatus == 0 else {
        throw Failure.profilerRecorderFailed(recorder.terminationStatus)
      }
      guard FileManager.default.fileExists(atPath: trace.path) else {
        throw Failure.profilerTraceMissing
      }
      guard !process.isTerminated, process.terminate() else { throw Failure.quitFailed }
      try await wait { process.isTerminated }
      try await verify(fixture)
      let export = Process()
      export.executableURL = URL(filePath: "/usr/bin/xcrun")
      export.arguments = [
        "xctrace", "export", "--input", trace.path, "--toc", "--output",
        trace.deletingPathExtension().appendingPathExtension("xml").path,
      ]
      try export.run()
      do { try await wait { !export.isRunning } } catch {
        if export.isRunning { kill(export.processIdentifier, SIGKILL) }
        throw error
      }
      guard export.terminationReason == .exit, export.terminationStatus == 0 else {
        throw Failure.launchFailed
      }
    } catch {
      if recorder.isRunning {
        recorder.interrupt()
        try? await wait { !recorder.isRunning }
        if recorder.isRunning { kill(recorder.processIdentifier, SIGKILL) }
      }
      if let owned, !owned.isTerminated {
        _ = owned.terminate()
        try? await wait { owned.isTerminated }
        if !owned.isTerminated { owned.forceTerminate() }
      }
      throw error
    }
  }

  private static func prepare(_ app: URL, _ manifestURL: URL) async throws {
    for value in [nil, "invalid-workspace"] as [String?] {
      let child = Process()
      child.executableURL = app.appending(path: "Contents/MacOS/NoteHushPerformance")
      var environment = ProcessInfo.processInfo.environment
      environment["NOTEHUSH_TEST_WORKSPACE"] = value
      child.environment = environment
      child.standardOutput = FileHandle.nullDevice
      child.standardError = FileHandle.nullDevice
      try child.run()
      do { try await wait { !child.isRunning } } catch {
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        throw Failure.missingGuard
      }
      guard child.terminationReason == .exit, child.terminationStatus == EX_CONFIG else {
        throw Failure.missingGuard
      }
    }
    var owned: [UUID] = []
    do {
      var fixtures: [Fixture] = []
      for name in names {
        let workspace = UUID()
        owned.append(workspace)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.allowsRunningApplicationSubstitution = false
        configuration.environment = ["NOTEHUSH_TEST_WORKSPACE": workspace.uuidString]
        let process = try await NSWorkspace.shared.openApplication(
          at: app, configuration: configuration)
        do {
          guard process.bundleURL?.standardizedFileURL == app else { throw Failure.wrongBuild }
          // Observe only publication, without contending for the live writer lock.
          try await wait {
            !process.isTerminated
              && FileManager.default.fileExists(
                atPath: root(workspace).appending(path: "session.json").path)
          }
          guard process.terminate() else { throw Failure.quitFailed }
          try await wait { process.isTerminated }
        } catch {
          if !process.isTerminated { process.forceTerminate() }
          try? await wait { process.isTerminated }
          throw error
        }
        let store = RecoveryStore(directory: root(workspace))
        guard let initial = try await store.load().snapshot, initial.revision < UInt64.max else {
          throw Failure.checkpointMissing
        }
        let open = name == "empty" ? 1 : name == "fiveMiB" ? 20 : 100
        let closed = name == "thirtyMiB" ? 20 : 0
        let tabs = (0..<open).map { TabSnapshot(text: text($0, empty: name == "empty")) }
        let history = (0..<closed).map {
          ClosedTabSnapshot(
            tab: TabSnapshot(text: text(open + $0, empty: false)), originalIndex: $0)
        }
        let snapshot = WorkspaceSnapshot(
          revision: initial.revision + 1, tabs: tabs, selectedTabID: tabs[open - 1].id,
          closedTabs: history)
        try await store.commit(snapshot)
        fixtures.append(
          Fixture(
            name: name, workspace: workspace, selectedTab: snapshot.selectedTabID,
            tabIDs: tabs.map(\.id), tabDigests: tabs.map { digest($0.text) },
            closedIDs: history.map { $0.tab.id },
            closedDigests: history.map { digest($0.tab.text) },
            seedRevision: snapshot.revision))
      }
      let environment = Environment(
        capturedAt: Date(), lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
        thermalState: ProcessInfo.processInfo.thermalState.rawValue,
        screens: NSScreen.screens.map {
          Screen(
            widthPoints: $0.frame.width, heightPoints: $0.frame.height, scale: $0.backingScaleFactor
          )
        })
      let manifest = Manifest(
        version: 1, applicationURL: app, fixtures: fixtures, environment: environment)
      try JSONEncoder().encode(manifest).write(to: manifestURL, options: .withoutOverwriting)
    } catch {
      // Leave evidence rather than deleting a workspace while an app still owns it.
      if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
        for workspace in owned { try? remove(workspace) }
      }
      throw error
    }
  }

  private static func verify(_ fixture: Fixture) async throws {
    guard
      let recovered = try await RecoveryStore(directory: root(fixture.workspace)).load().snapshot,
      recovered.revision > fixture.seedRevision,
      recovered.tabs.map(\.id) == fixture.tabIDs,
      recovered.tabs.map({ digest($0.text) }) == fixture.tabDigests,
      recovered.selectedTabID == fixture.selectedTab,
      (recovered.closedTabs ?? []).map({ $0.tab.id }) == fixture.closedIDs,
      (recovered.closedTabs ?? []).map({ digest($0.tab.text) }) == fixture.closedDigests
    else { throw Failure.fixtureMismatch }
  }

  private static func requireStopped() throws {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
      throw Failure.appRunning
    }
  }
  private static func root(_ workspace: UUID) -> URL {
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path:
        "Library/Containers/\(bundleID)/Data/Library/Application Support/NoteHush/UITests/\(workspace.uuidString)"
    )
  }
  private static func remove(_ workspace: UUID) throws {
    let directory = root(workspace)
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }
  private static func wait(_ predicate: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(20))
    while !predicate() {
      guard clock.now < deadline else { throw Failure.launchFailed }
      try await clock.sleep(until: clock.now.advanced(by: .milliseconds(20)))
    }
  }
  private static func text(_ index: Int, empty: Bool) -> String {
    if empty { return "" }
    let bytes = 256 * 1024
    let line = index % 2 == 0 ? "generated line\r\n" : "خط e\u{301} 📝.\r\n"
    let text =
      String(format: "tab-%010d\r\n", index)
      + String(repeating: line, count: bytes / 16 - 1)
    precondition(text.utf8.count == bytes)
    return text
  }
  private static func digest(_ text: String) -> Data { Data(SHA256.hash(data: Data(text.utf8))) }
}
