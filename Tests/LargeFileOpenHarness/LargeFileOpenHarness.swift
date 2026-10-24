import AppKit
import CryptoKit
import NativeFixtureSupport
import NoteHushCore

/// Host-only LaunchServices workload. No app runtime code, input events or AX access.
@main
@MainActor
enum LargeFileOpenHarness {
  static func main() async {
    umask(0o077)
    do {
      let arguments = CommandLine.arguments
      let diagnostic: Bool
      let byteCount: Int
      if arguments.count == 3 {
        diagnostic = false
        byteCount = LargeOpenWorkload.byteCount
      } else if arguments.count == 5, arguments[3] == "--paragraph",
        let requested = Int(arguments[4]), requested >= 16,
        requested <= LargeOpenWorkload.byteCount, requested.isMultiple(of: 8)
      {
        diagnostic = true
        byteCount = requested
      } else {
        throw OpenFailure.arguments
      }
      let workloads: [LargeOpenWorkload] =
        diagnostic
        ? [.arabicEmojiParagraph] : LargeOpenWorkload.allCases
      let observations = diagnostic ? 1 : LargeOpenWorkload.observations
      let run = try LargeOpenRun(
        application: URL(filePath: arguments[1], directoryHint: .isDirectory),
        output: URL(filePath: arguments[2], directoryHint: .isDirectory),
        workloads: workloads, observations: observations, byteCount: byteCount)
      try await run.collect()
      print(
        diagnostic
          ? "Long paragraph diagnostic completed; inspect per-case result and recovery evidence"
          : "Large file opening: both complete workloads and recovery verification passed")
    } catch {
      let reason = (error as? OpenFailure)?.rawValue ?? "operationFailed"
      FileHandle.standardError.write(Data("Large file opening failed: \(reason)\n".utf8))
      exit(1)
    }
  }
}

enum OpenFailure: String, Error {
  case arguments, wrongBuild, existingOutput, appRunning, wrongProcess, inactiveApp
  case missingGuard, checkpointTimeout, fixtureMismatch, sourceChanged, quitFailed
  case evidenceWrite, invalidDuration
}

@MainActor
final class LargeOpenRun {
  static let bundleID = "pk.codehub.NoteHush.PerformanceTesting"
  let applicationURL: URL
  let outputURL: URL
  let log: OpenEvidenceLog
  private let workloads: [LargeOpenWorkload]
  private let observations: Int
  private let byteCount: Int
  private var owned: NSRunningApplication?

  init(
    application: URL, output: URL, workloads: [LargeOpenWorkload], observations: Int,
    byteCount: Int
  ) throws {
    applicationURL = application.standardizedFileURL
    outputURL = output.standardizedFileURL
    self.workloads = workloads
    self.observations = observations
    self.byteCount = byteCount
    guard let bundle = Bundle(url: applicationURL), bundle.bundleIdentifier == Self.bundleID,
      bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "NoteHushPerformance",
      bundle.object(forInfoDictionaryKey: "NoteHushRequiresTestWorkspace") as? String == "YES",
      bundle.object(forInfoDictionaryKey: "NoteHushPerformanceBuild") as? String == "YES"
    else { throw OpenFailure.wrongBuild }
    let name = outputURL.lastPathComponent
    let properties = try outputURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard name.hasPrefix("LargeOpen-"), UUID(uuidString: String(name.dropFirst(10))) != nil,
      properties.isDirectory == true, properties.isSymbolicLink != true,
      !FileManager.default.fileExists(atPath: outputURL.appending(path: "inputs").path)
    else { throw OpenFailure.existingOutput }
    try Self.requireStopped()
    log = try OpenEvidenceLog(url: outputURL.appending(path: "observations.jsonl"))
  }

  func collect() async throws {
    do {
      try log.append(
        OpenHeader(
          observationsPerWorkload: observations, bytesPerFile: byteCount, workloads: workloads))
      try await checkIsolationGuard()
      let inputDirectory = outputURL.appending(path: "inputs", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(
        at: inputDirectory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      try writeManifest()
      for workload in workloads {
        let data = Data(try workload.text(byteCount: byteCount).utf8)
        let source = inputDirectory.appending(path: workload.rawValue + ".txt")
        try data.write(to: source, options: .withoutOverwriting)
        let digest = Data(SHA256.hash(data: data)).base64EncodedString()
        for index in 0..<observations {
          try await sample(workload, index: index, source: source, bytes: data, digest: digest)
          print("Large file opening: \(workload.rawValue) observation \(index + 1) verified")
        }
      }
      try log.append(OpenFinish(verifiedObservations: workloads.count * observations))
      try log.close()
    } catch {
      // Retain every fixture and partial observation. Only this exact launch's
      // identified process may be terminated, and forced teardown cannot pass.
      if let owned, !owned.isTerminated {
        _ = owned.terminate()
        try? await wait(seconds: 20) { owned.isTerminated }
        if !owned.isTerminated { owned.forceTerminate() }
      }
      try? log.append(OpenRunFailure(code: (error as? OpenFailure)?.rawValue ?? "operationFailed"))
      try? log.close()
      throw error
    }
  }

  private func sample(
    _ workload: LargeOpenWorkload, index: Int, source: URL, bytes: Data, digest: String
  ) async throws {
    try Self.requireStopped()
    let workspace = UUID()
    let directory = Self.root(workspace)
    guard !FileManager.default.fileExists(atPath: directory.path) else {
      throw OpenFailure.existingOutput
    }
    try log.append(OpenAttempt(workload: workload, index: index, workspace: workspace))
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.allowsRunningApplicationSubstitution = false
    configuration.createsNewApplicationInstance = false
    configuration.environment = ["NOTEHUSH_TEST_WORKSPACE": workspace.uuidString]
    let process = try await NSWorkspace.shared.openApplication(
      at: applicationURL, configuration: configuration)
    try requireIdentity(process)
    owned = process
    try log.append(OpenProcess(workload: workload, index: index, pid: process.processIdentifier))
    let clock = ContinuousClock()
    let initial = try await checkpoint(
      directory, process: process, deadline: clock.now.advanced(by: .seconds(10)), active: false
    ) { snapshot in
      snapshot.tabs.count == 1 && snapshot.tabs[0].text.isEmpty
        && snapshot.tabs[0].file == nil && snapshot.tabs[0].selection == TextSelection()
        && snapshot.selectedTabID == snapshot.tabs[0].id
        && (snapshot.closedTabs ?? []).isEmpty && snapshot.windowFrame?.isValid == true
    }
    try await wait(seconds: 10) { process.isActive || process.isTerminated }
    try requireIdentity(process)
    guard process.isActive else { throw OpenFailure.inactiveApp }

    let started = clock.now
    let returned = try await NSWorkspace.shared.open(
      [source], withApplicationAt: applicationURL, configuration: configuration)
    let returnedAt = clock.now
    try requireIdentity(returned)
    guard returned.processIdentifier == process.processIdentifier else {
      throw OpenFailure.wrongProcess
    }
    let opened: WorkspaceSnapshot
    do {
      opened = try await checkpoint(
        directory, process: process, deadline: started.advanced(by: .seconds(10)), active: true
      ) { snapshot in
        snapshot.revision > initial.revision && snapshot.tabs.count == 2
          && snapshot.tabs[0].id == initial.tabs[0].id
          && snapshot.selectedTabID == snapshot.tabs[1].id
          && snapshot.tabs[1].file?.url.standardizedFileURL == source.standardizedFileURL
          && snapshot.tabs[1].text.utf8.elementsEqual(bytes)
      }
    } catch {
      if let failure = error as? OpenFailure, failure == .checkpointTimeout {
        let elapsed = try nanoseconds(started.duration(to: clock.now))
        try log.append(OpenTimeout(workload: workload, index: index, elapsedNanoseconds: elapsed))
        if workload == .arabicEmojiParagraph {
          try await profileTimedOutProcess(process, workload: workload, index: index)
        }
      }
      throw error
    }
    let observedAt = clock.now
    let elapsed = try nanoseconds(started.duration(to: observedAt))
    // Record timing before postconditions; a later failed assertion never loses
    // the observed duration or becomes a successfully verified sample.
    try log.append(
      OpenObservation(
        workload: workload, index: index, requestToCheckpointNanoseconds: elapsed,
        launchServicesReturnNanoseconds: try nanoseconds(started.duration(to: returnedAt)),
        withinObservationBound: elapsed <= 10_000_000_000))
    guard elapsed <= 10_000_000_000 else { throw OpenFailure.checkpointTimeout }
    try verify(opened, initial: initial, source: source, bytes: bytes, digest: digest)
    try requireIdentity(process)
    guard process.isActive else { throw OpenFailure.inactiveApp }
    guard process.terminate() else { throw OpenFailure.quitFailed }
    try await wait(seconds: 20) { process.isTerminated }
    owned = nil
    guard let final = try CheckpointReader.read(directory.appending(path: "session.json")),
      final.revision >= opened.revision, final.tabs.map(\.id) == opened.tabs.map(\.id),
      final.tabs[1].file == opened.tabs[1].file
    else { throw OpenFailure.fixtureMismatch }
    try verify(final, initial: initial, source: source, bytes: bytes, digest: digest)
    guard try Data(contentsOf: source) == bytes else { throw OpenFailure.sourceChanged }
    try log.append(OpenVerification(workload: workload, index: index))
  }

  private func verify(
    _ snapshot: WorkspaceSnapshot, initial: WorkspaceSnapshot, source: URL,
    bytes: Data, digest: String
  ) throws {
    guard snapshot.tabs.count == 2, snapshot.tabs[0] == initial.tabs[0],
      snapshot.selectedTabID == snapshot.tabs[1].id, (snapshot.closedTabs ?? []).isEmpty,
      (snapshot.preferences ?? EditorPreferences()) == (initial.preferences ?? EditorPreferences()),
      let frame = snapshot.windowFrame, let originalFrame = initial.windowFrame,
      frame.isValid, sameFrame(frame, originalFrame),
      snapshot.tabs[1].text.utf8.elementsEqual(bytes),
      snapshot.tabs[1].title == source.lastPathComponent,
      snapshot.tabs[1].selection == TextSelection(), let scroll = snapshot.tabs[1].scroll,
      scroll.anchor == 0, abs(scroll.offset + 16) <= 1,
      abs(scroll.horizontalOffset ?? 0) <= 1, let binding = snapshot.tabs[1].file,
      binding.url.standardizedFileURL == source.standardizedFileURL,
      binding.encoding == .utf8, binding.fileDigest == digest, binding.textDigest == digest,
      binding.bookmark?.isEmpty == false
    else { throw OpenFailure.fixtureMismatch }
    var information = stat()
    guard lstat(source.path, &information) == 0,
      information.st_mode & S_IFMT == S_IFREG,
      binding.identity.device == information.st_dev,
      binding.identity.inode == information.st_ino
    else { throw OpenFailure.sourceChanged }
  }

  private func sameFrame(_ left: WindowFrame, _ right: WindowFrame) -> Bool {
    zip([left.x, left.y, left.width, left.height], [right.x, right.y, right.width, right.height])
      .allSatisfy { abs($0 - $1) <= 1 }
  }

  private func checkpoint(
    _ directory: URL, process: NSRunningApplication, deadline: ContinuousClock.Instant,
    active: Bool, matches: (WorkspaceSnapshot) -> Bool
  ) async throws -> WorkspaceSnapshot {
    let clock = ContinuousClock()
    while clock.now < deadline {
      try requireIdentity(process)
      if active && !process.isActive { throw OpenFailure.inactiveApp }
      let primary = directory.appending(path: "session.json")
      if FileManager.default.fileExists(atPath: primary.path),
        let snapshot = try CheckpointReader.read(primary), matches(snapshot)
      {
        return snapshot
      }
      try await clock.sleep(until: clock.now.advanced(by: .milliseconds(25)))
    }
    throw OpenFailure.checkpointTimeout
  }

  private func requireIdentity(_ process: NSRunningApplication) throws {
    guard !process.isTerminated, process.bundleIdentifier == Self.bundleID,
      process.bundleURL?.standardizedFileURL == applicationURL
    else { throw OpenFailure.wrongProcess }
  }

  private func profileTimedOutProcess(
    _ app: NSRunningApplication, workload: LargeOpenWorkload, index: Int
  ) async throws {
    guard !app.isTerminated, app.bundleIdentifier == Self.bundleID,
      app.bundleURL?.standardizedFileURL == applicationURL
    else {
      try log.append(
        OpenProfile(
          workload: workload, index: index, pid: app.processIdentifier,
          status: "processUnavailable", exitCode: nil, outputBytes: nil, outputSHA256: nil))
      return
    }
    let output = outputURL.appending(path: "timeout-profile-\(UUID().uuidString).txt")
    guard !FileManager.default.fileExists(atPath: output.path) else {
      throw OpenFailure.evidenceWrite
    }
    let sampler = Process()
    sampler.executableURL = URL(filePath: "/usr/bin/sample")
    sampler.arguments = [
      String(app.processIdentifier), "2", "1", "-file", output.path,
    ]
    var environment: [String: String] = [:]
    for key in ["HOME", "TMPDIR", "USER", "LOGNAME", "PATH", "LANG", "LC_ALL"] {
      environment[key] = ProcessInfo.processInfo.environment[key]
    }
    sampler.environment = environment
    sampler.standardOutput = FileHandle.nullDevice
    sampler.standardError = FileHandle.nullDevice
    do {
      try sampler.run()
    } catch {
      try log.append(
        OpenProfile(
          workload: workload, index: index, pid: app.processIdentifier, status: "launchFailed",
          exitCode: nil, outputBytes: nil, outputSHA256: nil))
      return
    }

    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(10))
    while sampler.isRunning && clock.now < deadline {
      try await clock.sleep(until: clock.now.advanced(by: .milliseconds(50)))
    }
    if sampler.isRunning {
      sampler.terminate()
      try? await wait(seconds: 2) { !sampler.isRunning }
      if sampler.isRunning {
        kill(sampler.processIdentifier, SIGKILL)
        try? await wait(seconds: 2) { !sampler.isRunning }
      }
      try log.append(
        OpenProfile(
          workload: workload, index: index, pid: app.processIdentifier, status: "timedOut",
          exitCode: nil, outputBytes: nil, outputSHA256: nil))
      return
    }

    let result = sampler.terminationReason == .exit ? sampler.terminationStatus : nil
    guard result == 0, let data = try? Data(contentsOf: output), !data.isEmpty else {
      try log.append(
        OpenProfile(
          workload: workload, index: index, pid: app.processIdentifier, status: "failed",
          exitCode: result, outputBytes: nil, outputSHA256: nil))
      return
    }
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    try log.append(
      OpenProfile(
        workload: workload, index: index, pid: app.processIdentifier, status: "captured",
        exitCode: result, outputBytes: data.count, outputSHA256: digest))
  }

  private static func requireStopped() throws {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
      throw OpenFailure.appRunning
    }
  }

  private static func root(_ workspace: UUID) -> URL {
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path:
        "Library/Containers/\(bundleID)/Data/Library/Application Support/NoteHush/UITests/\(workspace.uuidString)"
    )
  }

  private func wait(seconds: Int, until predicate: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(seconds))
    while !predicate() {
      guard clock.now < deadline else { throw OpenFailure.checkpointTimeout }
      try await clock.sleep(until: clock.now.advanced(by: .milliseconds(20)))
    }
  }

  private func nanoseconds(_ duration: Duration) throws -> UInt64 {
    let parts = duration.components
    guard parts.seconds >= 0, parts.seconds < 1200, parts.attoseconds >= 0 else {
      throw OpenFailure.invalidDuration
    }
    return UInt64(parts.seconds) * 1_000_000_000 + UInt64(parts.attoseconds / 1_000_000_000)
  }

  private func checkIsolationGuard() async throws {
    for value in [nil, "invalid-workspace"] as [String?] {
      let child = Process()
      child.executableURL = applicationURL.appending(path: "Contents/MacOS/NoteHushPerformance")
      var environment: [String: String] = [:]
      for key in ["HOME", "TMPDIR", "USER", "LOGNAME", "PATH", "LANG", "LC_ALL"] {
        environment[key] = ProcessInfo.processInfo.environment[key]
      }
      environment["NOTEHUSH_TEST_WORKSPACE"] = value
      child.environment = environment
      child.standardOutput = FileHandle.nullDevice
      child.standardError = FileHandle.nullDevice
      try child.run()
      do { try await wait(seconds: 10) { !child.isRunning } } catch {
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        throw OpenFailure.missingGuard
      }
      guard child.terminationReason == .exit, child.terminationStatus == EX_CONFIG else {
        throw OpenFailure.missingGuard
      }
    }
  }

  private func writeManifest() throws {
    let manifest = OpenManifest(
      applicationURL: applicationURL,
      environment: OpenEnvironment(
        capturedAt: Date(), lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
        thermalState: ProcessInfo.processInfo.thermalState.rawValue,
        screens: NSScreen.screens.map {
          OpenScreen(
            widthPoints: $0.frame.width, heightPoints: $0.frame.height,
            scale: $0.backingScaleFactor)
        }),
      fixtures: workloads.map { OpenFixture(name: $0.rawValue) })
    try JSONEncoder().encode(manifest).write(
      to: outputURL.appending(path: "fixtures.json"), options: .withoutOverwriting)
  }
}
