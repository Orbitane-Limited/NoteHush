import Foundation
import NoteHushCore

/// Test-only child process. Never included in the app or release archive.
@main
enum RecoveryCrashHarness {
  static func main() async throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 3 else { throw HarnessError.arguments }
    let store = RecoveryStore(directory: URL(filePath: arguments[2], directoryHint: .isDirectory))
    if arguments[1] == "write" {
      var workspace = WorkspaceSnapshot.empty()
      for revision in 1...1000 {
        workspace.revision = UInt64(revision)
        workspace.tabs[0].text = String(repeating: "revision:\(revision)\n", count: 8192)
        try await store.commit(workspace)
        FileHandle.standardOutput.write(Data("\(revision)\n".utf8))
      }
    } else if arguments[1] == "read" {
      guard let workspace = try await store.load().snapshot else { throw HarnessError.missing }
      try workspace.validate()
      let expected = String(repeating: "revision:\(workspace.revision)\n", count: 8192)
      guard workspace.tabs[0].text == expected else { throw HarnessError.partialSnapshot }
      FileHandle.standardOutput.write(Data("\(workspace.revision)\n".utf8))
    } else {
      throw HarnessError.arguments
    }
  }

  private enum HarnessError: Error { case arguments, missing, partialSnapshot }
}
