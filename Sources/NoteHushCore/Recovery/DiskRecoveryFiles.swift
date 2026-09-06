import Darwin
import Foundation

/// Synchronous operations are used only from the recovery actor. This boundary
/// allows deterministic read/write failures without damaging a user's filesystem.
package protocol RecoveryFiles: Sendable {
  func read(_ name: String) throws -> Data?
  func writeAtomically(_ data: Data, named name: String) throws
  func synchronizeDirectory() throws
  func withExclusiveAccess<T>(_ operation: () throws -> T) throws -> T
}

/// The child-process harness pauses at these actual filesystem boundaries.
/// No observer is installed by the app, and no environment flag enables one.
package enum RecoveryWritePhase: String, CaseIterable, Sendable {
  case temporaryWritten
  case fileSynchronized
  case renamed
  case directorySynchronized
}

package struct DiskRecoveryFiles: RecoveryFiles {
  let directory: URL
  private let observe: (@Sendable (String, RecoveryWritePhase) throws -> Void)?

  package init(
    directory: URL,
    observe: (@Sendable (String, RecoveryWritePhase) throws -> Void)? = nil
  ) {
    self.directory = directory
    self.observe = observe
  }

  package func read(_ name: String) throws -> Data? {
    do {
      let handle = try FileHandle(forReadingFrom: directory.appendingPathComponent(name))
      defer { try? handle.close() }
      var data = Data()
      while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
        guard data.count <= RecoveryStore.maximumEnvelopeBytes - chunk.count else {
          throw RecoveryError.snapshotTooLarge
        }
        data.append(chunk)
      }
      return data
    } catch let error as CocoaError
      where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
    {
      return nil
    } catch let error as NSError
      where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
    {
      return nil
    } catch let error as RecoveryError {
      throw error
    } catch {
      throw RecoveryError.storageUnavailable
    }
  }

  package func withExclusiveAccess<T>(_ operation: () throws -> T) throws -> T {
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: directory.path)
    } catch { throw RecoveryError.storageUnavailable }

    let lock = open(
      directory.appendingPathComponent(".lock").path,
      O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard lock >= 0 else { throw RecoveryError.storageUnavailable }
    defer { close(lock) }
    guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw RecoveryError.busy }
    defer { _ = flock(lock, LOCK_UN) }
    return try operation()
  }

  package func writeAtomically(_ data: Data, named name: String) throws {
    let temporary = directory.appendingPathComponent(".pending-\(UUID().uuidString)")
    let destination = directory.appendingPathComponent(name)
    let descriptor = open(
      temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW,
      S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw RecoveryError.storageUnavailable }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer {
      try? handle.close()
      // Only remove this invocation's unique temporary file, never a generation.
      _ = unlink(temporary.path)
    }
    do {
      try handle.write(contentsOf: data)
      try observe?(name, .temporaryWritten)
      try handle.synchronize()
      try observe?(name, .fileSynchronized)
      try handle.close()
    } catch { throw RecoveryError.storageUnavailable }
    guard rename(temporary.path, destination.path) == 0 else {
      throw RecoveryError.storageUnavailable
    }
    try observe?(name, .renamed)
    try synchronizeDirectory()
    try observe?(name, .directorySynchronized)
  }

  package func synchronizeDirectory() throws {
    let directoryDescriptor = open(directory.path, O_RDONLY | O_DIRECTORY)
    guard directoryDescriptor >= 0 else { throw RecoveryError.storageUnavailable }
    defer { close(directoryDescriptor) }
    guard fsync(directoryDescriptor) == 0 else { throw RecoveryError.storageUnavailable }
  }
}
