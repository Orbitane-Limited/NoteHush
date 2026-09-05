import Darwin
import Foundation

/// The failure boundary is intentionally narrow: a failed publication must never
/// change a tab's saved baseline. Production writes use Foundation atomic replacement.
public protocol TextFilePublishing: Sendable {
  func publish(_ data: Data, to url: URL) throws
}

public struct AtomicTextFilePublisher: TextFilePublishing {
  public init() {}
  public func publish(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
  }
}

public protocol TextFileAccess: Sendable {
  func open(_ url: URL) async throws -> OpenedTextFile
  func save(
    _ text: String, encoding: TextFileEncoding, to url: URL, expected: FileBinding?,
    saveAs: Bool, protectedFiles: [FileBinding]
  ) async throws -> FileBinding
}

public actor TextFileService: TextFileAccess {
  private let publisher: any TextFilePublishing

  public init(publisher: any TextFilePublishing = AtomicTextFilePublisher()) {
    self.publisher = publisher
  }

  public func open(_ url: URL) throws -> OpenedTextFile {
    try Task.checkCancellation()
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    // File coordination itself can wait on special files. Reject them before
    // entering coordination, then validate the opened descriptor again inside.
    _ = try Self.identity(url)
    return try coordinatedRead(url) { location in
      let raw = try Self.read(location)
      let decoded = try TextDocumentCodec.decode(raw.data)
      try Task.checkCancellation()
      return OpenedTextFile(
        text: decoded.text,
        binding: FileBinding(
          url: location.resolvingSymlinksInPath().standardizedFileURL, identity: raw.identity,
          encoding: decoded.encoding,
          fileDigest: TextDocumentCodec.digest(raw.data),
          textDigest: TextDocumentCodec.textDigest(decoded.text)), byteCount: raw.data.count)
    }
  }

  /// `expected` protects existing documents. A panel-approved Save As to a new
  /// destination has no prior binding; its overwrite approval belongs to the panel.
  public func save(
    _ text: String, encoding: TextFileEncoding, to url: URL, expected: FileBinding?,
    saveAs: Bool = false, protectedFiles: [FileBinding] = []
  ) throws -> FileBinding {
    try Task.checkCancellation()
    let data = try TextDocumentCodec.encode(text, as: encoding)
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    if FileManager.default.fileExists(atPath: url.path) { _ = try Self.identity(url) }
    let coordinator = NSFileCoordinator()
    var coordinationError: NSError?
    var result: Result<FileBinding, Error>?
    coordinator.coordinate(
      writingItemAt: url.resolvingSymlinksInPath(), options: .forReplacing,
      error: &coordinationError
    ) { location in
      result = Result {
        try Task.checkCancellation()
        let currentIdentity = try? Self.identity(location)
        guard
          !protectedFiles.contains(where: {
            $0.url == location.standardizedFileURL || $0.identity == currentIdentity
          })
        else { throw TextFileError.alreadyOpen }
        if let expected,
          !saveAs || expected.url == location.standardizedFileURL
            || expected.identity == currentIdentity
        {
          let current: RawFile
          do { current = try Self.read(location) } catch { throw TextFileError.changedOnDisk }
          guard current.identity == expected.identity,
            TextDocumentCodec.digest(current.data) == expected.fileDigest
          else { throw TextFileError.changedOnDisk }
        }
        try Task.checkCancellation()
        try publisher.publish(data, to: location)
        // Do not observe cancellation after publication: report the completed save.
        let identity = try Self.identity(location)
        return FileBinding(
          url: location.standardizedFileURL, identity: identity, encoding: encoding,
          fileDigest: TextDocumentCodec.digest(data), textDigest: TextDocumentCodec.textDigest(text)
        )
      }
    }
    if let coordinationError { throw coordinationError }
    guard let result else { throw TextFileError.unavailable }
    return try result.get()
  }

  private func coordinatedRead<T>(_ url: URL, operation: (URL) throws -> T) throws -> T {
    let coordinator = NSFileCoordinator()
    var coordinationError: NSError?
    var result: Result<T, Error>?
    coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError)
    { location in
      result = Result { try operation(location) }
    }
    if let coordinationError { throw coordinationError }
    guard let result else { throw TextFileError.unavailable }
    return try result.get()
  }

  private struct RawFile {
    let data: Data
    let identity: FileIdentity
  }

  private static func descriptor(_ url: URL) throws -> (Int32, stat) {
    guard url.isFileURL else { throw TextFileError.unavailable }
    // A raced-in FIFO/device must not block the reader. Resolve symlinks under
    // file coordination and refuse a last-moment link replacement at open().
    let descriptor = Darwin.open(
      url.resolvingSymlinksInPath().path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
    guard descriptor >= 0 else { throw TextFileError.unavailable }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
      Darwin.close(descriptor)
      throw TextFileError.notRegularFile
    }
    guard info.st_size >= 0, info.st_size <= TextDocumentCodec.maximumFileBytes else {
      Darwin.close(descriptor)
      throw TextFileError.tooLarge
    }
    return (descriptor, info)
  }

  private static func identity(_ url: URL) throws -> FileIdentity {
    let (descriptor, info) = try descriptor(url)
    defer { Darwin.close(descriptor) }
    return FileIdentity(device: info.st_dev, inode: info.st_ino)
  }

  private static func read(_ url: URL) throws -> RawFile {
    let (descriptor, info) = try descriptor(url)
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var data = Data()
    // The fstat limit is checked before reserveCapacity; also bound a growing file.
    data.reserveCapacity(Int(info.st_size))
    while true {
      try Task.checkCancellation()
      guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
      guard data.count <= TextDocumentCodec.maximumFileBytes - chunk.count else {
        throw TextFileError.tooLarge
      }
      data.append(chunk)
    }
    return RawFile(data: data, identity: FileIdentity(device: info.st_dev, inode: info.st_ino))
  }
}
