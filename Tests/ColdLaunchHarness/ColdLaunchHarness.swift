import AppKit
import NoteHushCore

/// Host-only integration driver. Never linked into the app. It launches only the
/// separately identified UITesting build and owns every fixture it writes.
@main
@MainActor
enum ColdLaunchHarness {
  static func main() async {
    do {
      guard CommandLine.arguments.count == 2 else { throw Failure.arguments }
      try await Scenario(applicationURL: URL(filePath: CommandLine.arguments[1])).run()
      print(
        "Cold launch: missing/invalid workspace rejected; file event, dirty recovery and restart passed"
      )
    } catch {
      let reason = (error as? Failure).map { String(describing: $0) } ?? "fixtureOperationFailed"
      FileHandle.standardError.write(Data("Cold launch failed: \(reason)\n".utf8))
      exit(1)
    }
  }

  fileprivate enum Failure: Error {
    case arguments, wrongBuild, appAlreadyRunning, isolationGuardMissing
    case launchRejected, checkpointNotObserved, quitFailed, stateMismatch, sourceChanged
  }
}

@MainActor
private final class Scenario {
  typealias Failure = ColdLaunchHarness.Failure
  private let bundleID = "pk.codehub.NoteHush.UITesting"
  private let applicationURL: URL
  private let workspaceID = UUID()
  private let fixture: URL
  private let recovery: URL
  private var application: NSRunningApplication?

  init(applicationURL: URL) throws {
    self.applicationURL = applicationURL.standardizedFileURL
    guard let bundle = Bundle(url: self.applicationURL),
      bundle.bundleIdentifier == bundleID,
      bundle.object(forInfoDictionaryKey: "NoteHushRequiresTestWorkspace") as? String == "YES"
    else { throw Failure.wrongBuild }
    guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
      throw Failure.appAlreadyRunning
    }
    fixture = FileManager.default.temporaryDirectory.appending(
      path: "NoteHushColdLaunch-\(workspaceID)")
    recovery = FileManager.default.homeDirectoryForCurrentUser.appending(
      path:
        "Library/Containers/\(bundleID)/Data/Library/Application Support/NoteHush/UITests/\(workspaceID)"
    )
  }

  func run() async throws {
    try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    do {
      try await rejectUnisolatedLaunch(nil)
      try await rejectUnisolatedLaunch("invalid-fixture")
      let source = fixture.appending(path: "finder.txt")
      let bytes = Data("Finder cold launch\r\nاردو e\u{301} 👩🏽‍💻".utf8)
      try bytes.write(to: source)
      try await launch(file: source)
      let opened = try await checkpoint { snapshot in
        snapshot.tabs.count == 2 && snapshot.tabs.last?.file?.bookmark != nil
          && snapshot.tabs.last?.text.utf8.elementsEqual(bytes) == true
      }
      guard opened.selectedTabID == opened.tabs[1].id else { throw Failure.stateMismatch }
      try await quit()
      try requireSource(source, bytes)

      // Seed only our UUID fixture after the app has actually terminated.
      // Changing the external file proves cold recovery does not reread over a draft.
      let store = RecoveryStore(directory: recovery)
      guard var pending = try await store.load().snapshot else { throw Failure.stateMismatch }
      pending.revision += 1
      pending.tabs[0].text = "untitled draft 📝"
      pending.tabs[1].text = "dirty e\u{301} 👩🏽‍💻\r\nاردو"
      pending.tabs[1].selection = TextSelection(location: 2, length: 3)
      pending.selectedTabID = pending.tabs[0].id
      pending.closedTabs = [
        ClosedTabSnapshot(tab: TabSnapshot(text: "closed draft"), originalIndex: 1)
      ]
      var preferences = EditorPreferences()
      preferences.fontSize = 18
      preferences.appearance = .dark
      pending.preferences = preferences
      try await store.commit(pending)
      let external = Data("external change must survive Quit".utf8)
      try external.write(to: source)
      var expected = pending
      // Selecting the named tab proves the cold file event actually ran after
      // restoration, rather than merely observing the startup checkpoint.
      expected.selectedTabID = pending.tabs[1].id
      try await launch(file: source)
      _ = try await checkpoint { Self.matches($0, expected) }
      try await quit()
      try requireSource(source, external)
      guard let beforeRestart = try await store.load().snapshot else { throw Failure.stateMismatch }
      try await launch(file: nil)
      _ = try await checkpoint { Self.matches($0, beforeRestart) }
      try await quit()
      let final = try await store.load()
      guard let snapshot = final.snapshot, Self.matches(snapshot, expected) else {
        throw Failure.stateMismatch
      }
      try requireSource(source, external)
      try cleanup()
    } catch {
      // Failure cleanup targets only the process this driver created. A forced
      // teardown never counts as successful Quit and never hides a failing test.
      if let application, !application.isTerminated {
        application.forceTerminate()
        try? await waitUntil { application.isTerminated }
      }
      if application?.isTerminated != false { try? cleanup() }
      throw error
    }
  }

  private func rejectUnisolatedLaunch(_ value: String?) async throws {
    let child = Process()
    child.executableURL = applicationURL.appending(path: "Contents/MacOS/NoteHush")
    var environment = ProcessInfo.processInfo.environment
    environment["NOTEHUSH_TEST_WORKSPACE"] = value
    child.environment = environment
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice
    try child.run()
    do {
      try await waitUntil { !child.isRunning }
    } catch {
      if child.isRunning { kill(child.processIdentifier, SIGKILL) }
      throw Failure.isolationGuardMissing
    }
    guard child.terminationReason == .exit, child.terminationStatus == EX_CONFIG else {
      throw Failure.isolationGuardMissing
    }
  }

  private func launch(file: URL?) async throws {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
      throw Failure.appAlreadyRunning
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.allowsRunningApplicationSubstitution = false
    configuration.environment = ["NOTEHUSH_TEST_WORKSPACE": workspaceID.uuidString]
    do {
      if let file {
        application = try await NSWorkspace.shared.open(
          [file], withApplicationAt: applicationURL, configuration: configuration)
      } else {
        application = try await NSWorkspace.shared.openApplication(
          at: applicationURL, configuration: configuration)
      }
    } catch { throw Failure.launchRejected }
  }

  private func checkpoint(_ matches: (WorkspaceSnapshot) -> Bool) async throws -> WorkspaceSnapshot
  {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(10))
    while clock.now < deadline {
      guard application?.isTerminated == false else { throw Failure.launchRejected }
      // Do not create storage for a failed environment handoff; wait for the app.
      if FileManager.default.fileExists(atPath: recovery.appending(path: "session.json").path) {
        // Read the atomically replaced primary without taking the writer's lock;
        // test observation must not cause a production busy error.
        if let snapshot = try CheckpointReader.read(recovery.appending(path: "session.json")),
          matches(snapshot)
        {
          return snapshot
        }
      }
      try await clock.sleep(until: clock.now.advanced(by: .milliseconds(20)))
    }
    throw Failure.checkpointNotObserved
  }

  private func quit() async throws {
    guard let application, application.terminate() else { throw Failure.quitFailed }
    do { try await waitUntil { application.isTerminated } } catch { throw Failure.quitFailed }
  }

  private func waitUntil(_ predicate: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(10))
    while !predicate() {
      guard clock.now < deadline else { throw Failure.quitFailed }
      try await clock.sleep(until: clock.now.advanced(by: .milliseconds(20)))
    }
  }

  private static func matches(_ actual: WorkspaceSnapshot, _ expected: WorkspaceSnapshot) -> Bool {
    actual.revision > expected.revision
      && actual.tabs.map(\.id) == expected.tabs.map(\.id)
      && zip(actual.tabs, expected.tabs).allSatisfy { $0.text.utf8.elementsEqual($1.text.utf8) }
      && actual.selectedTabID == expected.selectedTabID
      && actual.tabs.last?.selection == expected.tabs.last?.selection
      && actual.tabs.last?.file == expected.tabs.last?.file
      && actual.closedTabs == expected.closedTabs && actual.preferences == expected.preferences
  }

  private func requireSource(_ source: URL, _ expected: Data) throws {
    guard try Data(contentsOf: source) == expected else { throw Failure.sourceChanged }
  }

  private func cleanup() throws {
    // Both paths were constructed here from a fresh UUID; no arbitrary-path cleanup.
    for url in [recovery, fixture] where FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }
}
