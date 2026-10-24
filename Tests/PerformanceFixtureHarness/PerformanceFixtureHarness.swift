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
  static let interactionNames = ["typingASCII", "typingMixed", "switchASCII", "switchMixed"]

  struct Fixture: Codable {
    let name: String
    let workspace: UUID
    let selectedTab: UUID
    let tabIDs: [UUID]
    let tabDigests: [Data]
    let closedIDs: [UUID]
    let closedDigests: [Data]
    let seedRevision: UInt64
    let targetTab: UUID?
    let tabSelections: [TextSelection]
    let tabScrolls: [TextScrollPosition?]
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
    case arguments, wrongBuild, wrongProcess, appRunning, wrongManifest, missingGuard
    case launchFailed, checkpointMissing, quitFailed, fixtureMismatch
    case profilerTimedOut, profilerTraceMissing
    case allocationHistoryFailed(Int32)
    case profilerRecorderFailed(Int32)
  }

  static func main() async {
    do {
      guard CommandLine.arguments.count == 4,
        [
          "prepare", "prepare-interactions", "prepare-idle", "idle", "verify", "cleanup",
          "profile", "profile-idle",
        ]
        .contains(
          CommandLine.arguments[1])
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
      if ["prepare", "prepare-interactions", "prepare-idle"].contains(command) {
        guard !FileManager.default.fileExists(atPath: manifestURL.path) else {
          throw Failure.wrongManifest
        }
        try await prepare(
          app, manifestURL,
          scenarios: command == "prepare-idle"
            ? IdleResourceMeasurement.names
            : command == "prepare" ? names : interactionNames)
      } else {
        let manifest = try JSONDecoder().decode(
          Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.version == 1, manifest.applicationURL == app,
          [names, interactionNames, IdleResourceMeasurement.names].contains(
            manifest.fixtures.map(\.name)),
          Set(manifest.fixtures.map(\.workspace)).count == manifest.fixtures.count
        else { throw Failure.wrongManifest }
        if command == "idle" {
          try await IdleResourceMeasurement.run(app, manifest, manifestURL)
        } else if command == "profile-idle" {
          try await profileIdleAllocations(app, manifest, manifestURL)
        } else if command == "profile" {
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
      let reason =
        (error as? Failure).map { String(describing: $0) }
        ?? IdleResourceMeasurement.failureCode(for: error) ?? "fixtureOperationFailed"
      FileHandle.standardError.write(Data("Performance fixtures failed: \(reason)\n".utf8))
      exit(1)
    }
  }

  private static func profileIdleAllocations(
    _ app: URL, _ manifest: Manifest, _ manifestURL: URL
  ) async throws {
    guard manifest.fixtures.map(\.name) == IdleResourceMeasurement.names else {
      throw Failure.wrongManifest
    }
    let logs = manifestURL.deletingLastPathComponent().appending(path: "allocations")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    for fixture in manifest.fixtures {
      try requireStopped()
      guard
        let before = try await RecoveryStore(directory: root(fixture.workspace)).load().snapshot,
        before.revision == fixture.seedRevision,
        before.tabs.map(\.id) == fixture.tabIDs,
        before.selectedTabID == fixture.selectedTab
      else { throw Failure.fixtureMismatch }

      let trace = logs.appending(path: "Allocations-\(fixture.name)-\(UUID().uuidString).trace")
      let recorder = Process()
      recorder.executableURL = URL(filePath: "/usr/bin/xcrun")
      var owned: NSRunningApplication?
      do {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.allowsRunningApplicationSubstitution = false
        configuration.environment = [
          "NOTEHUSH_TEST_WORKSPACE": fixture.workspace.uuidString,
          "MallocStackLogging": "lite",
        ]
        let process = try await NSWorkspace.shared.openApplication(
          at: app, configuration: configuration)
        guard process.bundleURL?.standardizedFileURL == app,
          process.bundleIdentifier == bundleID
        else { throw Failure.wrongBuild }
        owned = process

        // Let the recovered workspace reach the same fixed settled state as
        // the unprofiled idle run before starting the app-only allocation trace.
        let clock = ContinuousClock()
        let launched = clock.now
        for second in 1...30 {
          try await clock.sleep(until: launched.advanced(by: .seconds(second)))
          try requireProfileIdentity(process, app)
        }
        recorder.arguments = [
          "xctrace", "record", "--template", "Allocations", "--time-limit", "60s",
          "--output", trace.path, "--attach", String(process.processIdentifier), "--no-prompt",
        ]
        try recorder.run()
        // Preserve the 60-second sample but allow Instruments up to 3 minutes
        // to flush the larger call-stack-enabled trace after its time limit.
        let deadline = clock.now.advanced(by: .seconds(180))
        while recorder.isRunning {
          try requireProfileIdentity(process, app)
          guard clock.now < deadline else { throw Failure.profilerTimedOut }
          try await clock.sleep(until: clock.now.advanced(by: .milliseconds(100)))
        }
        guard recorder.terminationReason == .exit, recorder.terminationStatus == 0 else {
          throw Failure.profilerRecorderFailed(recorder.terminationStatus)
        }
        guard FileManager.default.fileExists(atPath: trace.path) else {
          throw Failure.profilerTraceMissing
        }
        try requireProfileIdentity(process, app)

        let traceBase = trace.deletingPathExtension()
        let allocationsXML = traceBase.appendingPathExtension("allocations.xml")
        let exports: [(selection: [String], output: URL)] = [
          (["--toc"], traceBase.appendingPathExtension("xml")),
          (
            [
              "--xpath",
              "/trace-toc/run[@number=\"1\"]/tracks/track[@name=\"Allocations\"]/details/detail[@name=\"Statistics\"]",
            ], traceBase.appendingPathExtension("statistics.xml")
          ),
          (
            [
              "--xpath",
              "/trace-toc/run[@number=\"1\"]/tracks/track[@name=\"Allocations\"]/details/detail[@name=\"Allocations List\"]",
            ], allocationsXML
          ),
        ]
        for export in exports {
          try requireProfileIdentity(process, app)
          let process = Process()
          process.executableURL = URL(filePath: "/usr/bin/xcrun")
          process.arguments =
            ["xctrace", "export", "--input", trace.path]
            + export.selection + ["--output", export.output.path]
          try process.run()
          do { try await wait { !process.isRunning } } catch {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw error
          }
          guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw Failure.launchFailed
          }
        }
        let historyScript = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
          .appending(path: "scripts/export_malloc_history.py")
        let historyOutput = traceBase.appendingPathExtension("malloc-history.txt")
        let history = Process()
        history.executableURL = URL(filePath: "/usr/bin/python3")
        history.arguments = [
          historyScript.path, String(process.processIdentifier), allocationsXML.path,
          historyOutput.path,
        ]
        try history.run()
        let historyDeadline = clock.now.advanced(by: .seconds(100))
        while history.isRunning {
          try requireProfileIdentity(process, app)
          guard clock.now < historyDeadline else {
            kill(history.processIdentifier, SIGKILL)
            throw Failure.profilerTimedOut
          }
          try await clock.sleep(until: clock.now.advanced(by: .milliseconds(50)))
        }
        guard history.terminationReason == .exit, history.terminationStatus == 0 else {
          throw Failure.allocationHistoryFailed(history.terminationStatus)
        }
        try requireProfileIdentity(process, app)
        guard process.terminate() else { throw Failure.quitFailed }
        try await wait { process.isTerminated }
        try await verify(fixture)
        try await IdleResourceMeasurement.verifyPresentation(fixture, before)
        print("Allocations trace: \(fixture.name) completed and fixture verified")
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
  }

  private static func requireProfileIdentity(_ process: NSRunningApplication, _ app: URL) throws {
    guard !process.isTerminated, process.bundleURL?.standardizedFileURL == app,
      process.bundleIdentifier == bundleID, process.isActive
    else { throw Failure.wrongProcess }
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

  private static func prepare(_ app: URL, _ manifestURL: URL, scenarios: [String]) async throws {
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
      for name in scenarios {
        let workspace = UUID()
        owned.append(workspace)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.allowsRunningApplicationSubstitution = false
        configuration.environment = ["NOTEHUSH_TEST_WORKSPACE": workspace.uuidString]
        let process = try await NSWorkspace.shared.openApplication(
          at: app, configuration: configuration)
        guard process.bundleURL?.standardizedFileURL == app, process.bundleIdentifier == bundleID
        else {
          throw Failure.wrongBuild
        }
        do {
          // Only this verified fixture process is eligible for failure cleanup.
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
        let interaction = interactionNames.contains(name)
        let typing = name.hasPrefix("typing")
        let open =
          interaction ? (typing ? 2 : 20) : name == "empty" ? 1 : name == "fiveMiB" ? 20 : 100
        let closed = interaction ? 2 : name == "thirtyMiB" ? 20 : 0
        let tabs = (0..<open).map { index -> TabSnapshot in
          let bytes = typing ? 1024 * 1024 : 256 * 1024
          var tab = TabSnapshot(text: text(index, empty: name == "empty", bytes: bytes))
          if interaction {
            let lineLength = (index % 2 == 0 ? "generated line\r\n" : "خط e\u{301} 📝.\r\n").utf16
              .count
            let anchor = 16 + (bytes / 16 / 2) * lineLength
            tab.selection = TextSelection(location: anchor + 10 * lineLength)
            tab.scroll = TextScrollPosition(anchor: anchor, offset: 3)
          } else if scenarios == IdleResourceMeasurement.names {
            // A declared idle viewport avoids guessing the app's inset-relative default.
            tab.scroll = TextScrollPosition(anchor: 0, offset: 0)
          }
          return tab
        }
        let target = interaction ? (name.hasSuffix("ASCII") ? open - 2 : open - 1) : open - 1
        let selected = interaction && !typing ? (target == open - 1 ? open - 2 : open - 1) : target
        let history = (0..<closed).map {
          ClosedTabSnapshot(
            tab: TabSnapshot(text: text(open + $0, empty: false)), originalIndex: $0)
        }
        let snapshot = WorkspaceSnapshot(
          revision: initial.revision + 1, tabs: tabs, selectedTabID: tabs[selected].id,
          closedTabs: history)
        try await store.commit(snapshot)
        fixtures.append(
          Fixture(
            name: name, workspace: workspace, selectedTab: snapshot.selectedTabID,
            tabIDs: tabs.map(\.id), tabDigests: tabs.map { digest($0.text) },
            closedIDs: history.map { $0.tab.id },
            closedDigests: history.map { digest($0.tab.text) },
            seedRevision: snapshot.revision, targetTab: interaction ? tabs[target].id : nil,
            tabSelections: tabs.map(\.selection), tabScrolls: tabs.map(\.scroll)))
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

  static func verify(_ fixture: Fixture) async throws {
    guard
      let recovered = try await RecoveryStore(directory: root(fixture.workspace)).load().snapshot,
      recovered.revision > fixture.seedRevision,
      recovered.tabs.map(\.id) == fixture.tabIDs,
      recovered.tabs.map({ digest($0.text) }) == fixture.tabDigests,
      recovered.selectedTabID == fixture.selectedTab,
      (recovered.closedTabs ?? []).map({ $0.tab.id }) == fixture.closedIDs,
      (recovered.closedTabs ?? []).map({ digest($0.tab.text) }) == fixture.closedDigests
    else { throw Failure.fixtureMismatch }
    if fixture.targetTab != nil {
      guard recovered.tabs.map(\.selection) == fixture.tabSelections,
        recovered.tabs.count == fixture.tabScrolls.count
      else { throw Failure.fixtureMismatch }
      for (tab, expected) in zip(recovered.tabs, fixture.tabScrolls) {
        guard let expected, let actual = tab.scroll,
          logicalLine(tab.text, expected.anchor) >= 0,
          logicalLine(tab.text, actual.anchor) == logicalLine(tab.text, expected.anchor),
          abs(actual.offset - expected.offset) <= 1,
          abs(actual.horizontalOffset ?? 0) <= 1
        else { throw Failure.fixtureMismatch }
      }
    }
  }

  private static func logicalLine(_ text: String, _ offset: Int) -> Int {
    guard (0...text.utf16.count).contains(offset) else { return -1 }
    return text.utf16.prefix(offset).filter { $0 == 0x0A }.count
  }

  static func requireStopped() throws {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
      throw Failure.appRunning
    }
  }
  static func root(_ workspace: UUID) -> URL {
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
  static func wait(_ predicate: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(20))
    while !predicate() {
      guard clock.now < deadline else { throw Failure.launchFailed }
      try await clock.sleep(until: clock.now.advanced(by: .milliseconds(20)))
    }
  }
  private static func text(_ index: Int, empty: Bool, bytes: Int = 256 * 1024) -> String {
    if empty { return "" }
    let line = index % 2 == 0 ? "generated line\r\n" : "خط e\u{301} 📝.\r\n"
    let text =
      String(format: "tab-%010d\r\n", index)
      + String(repeating: line, count: bytes / 16 - 1)
    precondition(text.utf8.count == bytes)
    return text
  }
  private static func digest(_ text: String) -> Data { Data(SHA256.hash(data: Data(text.utf8))) }
}
