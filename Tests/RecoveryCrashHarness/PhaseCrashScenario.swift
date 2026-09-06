import Foundation
import NoteHushCore
import os

/// All paths originate in the host's newly-created temporary directory. This
/// executable and its package-only I/O observer are never configured by the app.
enum PhaseCrashScenario {
  private enum Mode: String { case first, update, clear }
  private enum Target: String { case backup, primary, cleanup }
  private enum Failure: Error { case arguments, gateNotReached, resumed, recoveryMismatch }

  private struct Oracle: Codable {
    let before: WorkspaceSnapshot?
    let after: WorkspaceSnapshot
    let sourceBytes: Data
  }

  static func write(_ arguments: [String]) async throws {
    guard arguments.count == 6,
      let mode = Mode(rawValue: arguments[3]),
      let target = Target(rawValue: arguments[4]),
      let phase = RecoveryWritePhase(rawValue: arguments[5]),
      target != .cleanup || mode == .clear
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
    if mode != .first { try await RecoveryStore(directory: directory).commit(initial) }
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
      sourceBytes: try Data(contentsOf: source))
    try canonical(oracle).write(to: root.appending(path: "oracle.json"), options: .atomic)

    let name = target == .primary ? "session.json" : "session.previous.json"
    let occurrence = target == .cleanup ? 2 : 1
    let counter = OSAllocatedUnfairLock(initialState: 0)
    let files = DiskRecoveryFiles(directory: directory) { writtenName, writtenPhase in
      guard writtenName == name, writtenPhase == phase else { return }
      let stop = counter.withLock { count in
        count += 1
        return count == occurrence
      }
      guard stop else { return }
      FileHandle.standardOutput.write(Data("paused\n".utf8))
      // Keep the process inside the real write until the parent sends SIGKILL.
      // EOF or an unexpected release is a test failure, never a passing drill.
      _ = try FileHandle.standardInput.read(upToCount: 1)
      throw Failure.resumed
    }
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
    FileHandle.standardOutput.write(Data("\(loaded.snapshot?.revision ?? 0)\n".utf8))
  }

  private static func canonical<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }
}
