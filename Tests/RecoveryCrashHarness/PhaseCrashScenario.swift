import CryptoKit
import Foundation
import NoteHushCore
import os

/// All paths originate in the host's newly-created temporary directory. This
/// executable and its package-only I/O observer are never configured by the app.
enum PhaseCrashScenario {
  private enum Mode: String { case first, update, clear, migrate, repair }
  private enum Target: String {
    case blob, backup, primary, cleanup, reclaim, evidenceBlob, evidenceManifest
  }
  private enum Failure: Error { case arguments, gateNotReached, resumed, recoveryMismatch }

  private struct Oracle: Codable {
    let before: WorkspaceSnapshot?
    let after: WorkspaceSnapshot
    let sourceBytes: Data
    let damaged: [String: Data]?
  }

  static func write(_ arguments: [String]) async throws {
    guard arguments.count == 6,
      let mode = Mode(rawValue: arguments[3]),
      let target = Target(rawValue: arguments[4]),
      target != .cleanup || mode == .clear,
      target != .reclaim || mode == .clear,
      target == .reclaim
        ? RecoveryRemovalPhase(rawValue: arguments[5]) != nil
        : RecoveryWritePhase(rawValue: arguments[5]) != nil
    else { throw Failure.arguments }
    let root = URL(filePath: arguments[2], directoryHint: .isDirectory)
    let source = root.appending(path: "source.txt")
    let binding = try await TextFileService().save(
      "original\r\nاردو 👩🏽‍💻", encoding: .utf16LE, to: source, expected: nil, saveAs: true)
    let first = TabSnapshot(
      title: "source.txt", text: String(repeating: "dirty\r\ne\u{301} 👩🏽‍💻\n", count: 2048),
      selection: TextSelection(location: 2, length: 3),
      scroll: TextScrollPosition(anchor: 0, offset: 3, horizontalOffset: 22), file: binding)
    let second = TabSnapshot(text: "untitled\nاردو", selection: TextSelection(location: 3))
    let closed = ClosedTabSnapshot(
      tab: TabSnapshot(text: "closed unsaved draft 📝"), originalIndex: 1)
    var preferences = EditorPreferences()
    preferences.fontSize = 18
    preferences.appearance = .dark
    preferences.wordWrap = false
    let initial = WorkspaceSnapshot(
      revision: 1, tabs: [first, second], selectedTabID: second.id,
      windowFrame: WindowFrame(x: 12, y: 34, width: 820, height: 540),
      preferences: preferences, closedTabs: [closed])
    let directory = root.appending(path: "Recovery", directoryHint: .isDirectory)
    if mode == .migrate {
      let payload = try canonical(initial)
      let legacy = try JSONSerialization.data(
        withJSONObject: [
          "version": 5, "payload": payload.base64EncodedString(),
          "sha256": Data(SHA256.hash(data: payload)).base64EncodedString(),
        ], options: [.sortedKeys])
      let files = DiskRecoveryFiles(directory: directory)
      try files.withExclusiveAccess {
        try files.writeAtomically(legacy, named: "session.previous.json")
        try files.writeAtomically(legacy, named: "session.json")
      }
    } else if mode != .first {
      try await RecoveryStore(directory: directory).commit(initial)
    }
    var damaged: [String: Data]?
    if mode == .repair {
      var entries: [String: Data] = ["session.json": Data("damaged fixture manifest".utf8)]
      for name in try FileManager.default.contentsOfDirectory(atPath: directory.path)
      where name.hasPrefix("blob-") {
        entries[name] = try Data(contentsOf: directory.appending(path: name))
      }
      try entries["session.json"]?.write(to: directory.appending(path: "session.json"))
      damaged = entries
    }
    var pending = initial
    if mode != .first {
      pending.revision = 2
      pending.tabs.reverse()
      pending.selectedTabID = first.id
      pending.tabs[0].text += "\nlatest input"
      pending.tabs[1].text += "unsaved suffix"
      pending.preferences?.zoomPercent = 150
    }
    if mode == .clear { pending.closedTabs = [] }
    let oracle = Oracle(
      before: mode == .first ? nil : initial, after: pending,
      sourceBytes: try Data(contentsOf: source), damaged: damaged)
    try canonical(oracle).write(to: root.appending(path: "oracle.json"), options: .atomic)

    let name = target == .primary ? "session.json" : "session.previous.json"
    let occurrence = target == .cleanup ? 2 : 1
    let counter = OSAllocatedUnfairLock(initialState: 0)
    let pause: @Sendable () throws -> Void = {
      FileHandle.standardOutput.write(Data("paused\n".utf8))
      _ = try FileHandle.standardInput.read(upToCount: 1)
      throw Failure.resumed
    }
    let requestedPhase = arguments[5]
    let files = DiskRecoveryFiles(
      directory: directory,
      observeRemoval: { _, phase in
        if target == .reclaim, phase.rawValue == requestedPhase { try pause() }
      },
      observe: { writtenName, writtenPhase in
        let matches: Bool
        switch target {
        case .blob: matches = writtenName.hasPrefix("blob-")
        case .evidenceBlob:
          matches = writtenName.hasPrefix("damaged-") && writtenName.contains("--blob-")
        case .evidenceManifest:
          matches = writtenName.hasPrefix("damaged-") && writtenName.hasSuffix("--session.json")
        case .reclaim: matches = false
        default: matches = writtenName == name
        }
        guard matches, writtenPhase.rawValue == requestedPhase else { return }
        let stop = counter.withLock { count in
          count += 1
          return count == occurrence
        }
        guard stop else { return }
        // Keep the process inside the real write until the parent sends SIGKILL.
        // EOF or an unexpected release is a test failure, never a passing drill.
        try pause()
      })
    try await RecoveryStore(files: files).commit(pending)
    throw Failure.gateNotReached
  }

  static func read(_ root: URL) async throws {
    let oracle = try JSONDecoder().decode(
      Oracle.self, from: Data(contentsOf: root.appending(path: "oracle.json")))
    let loaded = try await RecoveryStore(directory: root.appending(path: "Recovery")).load()
    if let snapshot = loaded.snapshot {
      try snapshot.validate()
      let expected = snapshot.revision == oracle.after.revision ? oracle.after : oracle.before
      guard let expected, try canonical(snapshot) == canonical(expected) else {
        throw Failure.recoveryMismatch
      }
    } else if oracle.before != nil {
      throw Failure.recoveryMismatch
    }
    guard try Data(contentsOf: root.appending(path: "source.txt")) == oracle.sourceBytes else {
      throw Failure.recoveryMismatch
    }
    if let damaged = oracle.damaged {
      let directory = root.appending(path: "Recovery")
      let primary = try Data(contentsOf: directory.appending(path: "session.json"))
      var prefix = ""
      if primary != damaged["session.json"] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        guard
          let evidence = names.first(where: {
            $0.hasPrefix("damaged-") && $0.hasSuffix("--session.json")
          })
        else { throw Failure.recoveryMismatch }
        prefix = String(evidence.dropLast("session.json".count))
      }
      for (name, bytes) in damaged {
        guard try Data(contentsOf: directory.appending(path: prefix + name)) == bytes else {
          throw Failure.recoveryMismatch
        }
      }
    }
    FileHandle.standardOutput.write(Data("\(loaded.snapshot?.revision ?? 0)\n".utf8))
  }

  private static func canonical<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }
}
