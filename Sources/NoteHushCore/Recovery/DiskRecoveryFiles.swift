import Darwin
import Foundation

/// Synchronous operations are used only from the recovery actor. This boundary
/// allows deterministic read/write failures without damaging a user's filesystem.
package protocol RecoveryFiles: Sendable {
  func read(_ name: String) throws -> Data?
  func fingerprint(_ name: String) throws -> RecoveryFileFingerprint?
  func names() throws -> [String]
  func remove(_ name: String) throws
  func writeAtomically(_ data: Data, named name: String) throws
  func synchronizeDirectory() throws
  func withExclusiveAccess<T>(_ operation: () throws -> T) throws -> T
}

/// A warm cache is valid only for the same regular file and filesystem metadata.
/// Fresh loads still verify bytes. This is not a substitute for a disk integrity check.
package struct RecoveryFileFingerprint: Equatable, Sendable {
  let device: Int32
  let inode: UInt64
  let size: Int64
  let mode: UInt16
  let owner: UInt32
  let group: UInt32
  let modifiedSeconds: Int
  let modifiedNanoseconds: Int
  let changedSeconds: Int
  let changedNanoseconds: Int

  init(_ value: stat) {
    device = value.st_dev
    inode = value.st_ino
    size = value.st_size
    mode = value.st_mode
    owner = value.st_uid
    group = value.st_gid
    modifiedSeconds = value.st_mtimespec.tv_sec
    modifiedNanoseconds = value.st_mtimespec.tv_nsec
    changedSeconds = value.st_ctimespec.tv_sec
    changedNanoseconds = value.st_ctimespec.tv_nsec
  }
}

/// The child-process harness pauses at these actual filesystem boundaries.
/// No observer is installed by the app, and no environment flag enables one.
package enum RecoveryWritePhase: String, CaseIterable, Sendable {
  case temporaryWritten
  case fileSynchronized
  case renamed
  case directorySynchronized
}

package enum RecoveryRemovalPhase: String, CaseIterable, Sendable {
  case unlinked
  case directorySynchronized
}

package struct DiskRecoveryFiles: RecoveryFiles {
  let directory: URL
  private let observe: (@Sendable (String, RecoveryWritePhase) throws -> Void)?
  private let observeRemoval: (@Sendable (String, RecoveryRemovalPhase) throws -> Void)?

  package init(
    directory: URL,
    observe: (@Sendable (String, RecoveryWritePhase) throws -> Void)? = nil
  ) {
    self.directory = directory
    self.observe = observe
    observeRemoval = nil
  }

  package init(
    directory: URL,
    observeRemoval: @escaping @Sendable (String, RecoveryRemovalPhase) throws -> Void,
    observe: @escaping @Sendable (String, RecoveryWritePhase) throws -> Void
  ) {
    self.directory = directory
    self.observe = observe
    self.observeRemoval = observeRemoval
  }

  package func read(_ name: String) throws -> Data? {
    let url = try location(name)
    // O_NONBLOCK prevents opening a FIFO from stalling the recovery actor.
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard descriptor >= 0 else {
      if errno == ENOENT { return nil }
      throw RecoveryError.storageUnavailable
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var attributes = stat()
    guard fstat(descriptor, &attributes) == 0,
      attributes.st_mode & S_IFMT == S_IFREG, attributes.st_size >= 0
    else { throw RecoveryError.storageUnavailable }
    guard attributes.st_size <= RecoveryStore.maximumEnvelopeBytes else {
      throw RecoveryError.snapshotTooLarge
    }
    do {
      var data = Data()
      while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
        guard data.count <= RecoveryStore.maximumEnvelopeBytes - chunk.count else {
          throw RecoveryError.snapshotTooLarge
        }
        data.append(chunk)
      }
      var after = stat()
      guard fstat(descriptor, &after) == 0,
        RecoveryFileFingerprint(attributes) == RecoveryFileFingerprint(after),
        data.count == attributes.st_size
      else { throw RecoveryError.storageUnavailable }
      return data
    } catch let error as RecoveryError {
      throw error
    } catch {
      throw RecoveryError.storageUnavailable
    }
  }

  package func fingerprint(_ name: String) throws -> RecoveryFileFingerprint? {
    let url = try location(name)
    var attributes = stat()
    guard lstat(url.path, &attributes) == 0 else {
      if errno == ENOENT { return nil }
      throw RecoveryError.storageUnavailable
    }
    guard attributes.st_mode & S_IFMT == S_IFREG, attributes.st_size >= 0 else {
      throw RecoveryError.storageUnavailable
    }
    return RecoveryFileFingerprint(attributes)
  }

  package func names() throws -> [String] {
    do { return try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() } catch
    { throw RecoveryError.storageUnavailable }
  }

  package func remove(_ name: String) throws {
    let url = try location(name)
    // Validate the object even though unlink itself would not follow a link.
    guard try fingerprint(name) != nil else { return }
    guard unlink(url.path) == 0 else { throw RecoveryError.storageUnavailable }
    try observeRemoval?(name, .unlinked)
    try synchronizeDirectory()
    try observeRemoval?(name, .directorySynchronized)
  }

  private func location(_ name: String) throws -> URL {
    guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
      !name.utf8.contains(0)
    else { throw RecoveryError.storageUnavailable }
    return directory.appendingPathComponent(name)
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
    let destination = try location(name)
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
