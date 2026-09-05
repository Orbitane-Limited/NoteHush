import Darwin
import Foundation
import XCTest

@testable import NoteHushCore

@MainActor
final class TextFileServiceTests: XCTestCase {
  func testOpenSavePreservesFormatAndExactFilename() async throws {
    let fixture = try FileFixture()
    for encoding in TextFileEncoding.allCases {
      let url = fixture.directory.appending(path: "اردو notes.\(encoding.rawValue).config")
      let original = "👩🏽‍💻\r\ne\u{301}\nاردو\rtail"
      try TextDocumentCodec.encode(original, as: encoding).write(to: url)
      try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
      let service = TextFileService()
      let opened = try await service.open(url)
      XCTAssertEqual(opened.binding.encoding, encoding)
      let edited = original + "\nlast"
      let saved = try await service.save(
        edited, encoding: encoding, to: url, expected: opened.binding)
      XCTAssertEqual(saved.url.lastPathComponent, url.lastPathComponent)
      XCTAssertEqual(try Data(contentsOf: url), try TextDocumentCodec.encode(edited, as: encoding))
      XCTAssertEqual(saved.textDigest, TextDocumentCodec.textDigest(edited))
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o640)
    }
  }

  func testSaveAsCreatesExtensionlessFileAndProtectsOtherOpenFiles() async throws {
    let fixture = try FileFixture()
    let url = fixture.directory.appending(path: "no extension")
    let service = TextFileService()
    let binding = try await service.save(
      "first", encoding: .utf8, to: url, expected: nil, saveAs: true)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    do {
      _ = try await service.save(
        "second", encoding: .utf8, to: url, expected: nil,
        saveAs: true, protectedFiles: [binding])
      XCTFail("Must not overwrite a different open tab")
    } catch { XCTAssertEqual(error as? TextFileError, .alreadyOpen) }
    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "first")
  }

  func testChangedAndDeletedOriginalAreNeverOverwrittenOrRecreated() async throws {
    let fixture = try FileFixture()
    let url = fixture.directory.appending(path: "original.txt")
    try Data("original".utf8).write(to: url)
    let service = TextFileService()
    let opened = try await service.open(url)
    try Data("external".utf8).write(to: url, options: .atomic)
    do {
      _ = try await service.save("draft", encoding: .utf8, to: url, expected: opened.binding)
      XCTFail("External changes must block Save")
    } catch { XCTAssertEqual(error as? TextFileError, .changedOnDisk) }
    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "external")
    try FileManager.default.removeItem(at: url)
    do {
      _ = try await service.save("draft", encoding: .utf8, to: url, expected: opened.binding)
      XCTFail("Deleted sources must not be recreated")
    } catch { XCTAssertEqual(error as? TextFileError, .changedOnDisk) }
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testFailedPublicationLeavesOriginalIntact() async throws {
    let fixture = try FileFixture()
    let url = fixture.directory.appending(path: "safe.txt")
    try Data("original".utf8).write(to: url)
    let service = TextFileService(publisher: FailingTextPublisher())
    let opened = try await service.open(url)
    do {
      _ = try await service.save("new", encoding: .utf8, to: url, expected: opened.binding)
      XCTFail("Injected failure must be surfaced")
    } catch { XCTAssertEqual(error as? TextFileError, .unavailable) }
    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "original")
  }

  func testOversizeSparseFileAndSpecialFilesAreRejected() async throws {
    let fixture = try FileFixture()
    let huge = fixture.directory.appending(path: "huge.txt")
    XCTAssertTrue(FileManager.default.createFile(atPath: huge.path, contents: nil))
    let handle = try FileHandle(forWritingTo: huge)
    try handle.truncate(atOffset: UInt64(TextDocumentCodec.maximumFileBytes + 1))
    try handle.close()
    let service = TextFileService()
    do {
      _ = try await service.open(huge)
      XCTFail("Sparse file must fail its metadata guard")
    } catch { XCTAssertEqual(error as? TextFileError, .tooLarge) }
    let fifo = fixture.directory.appending(path: "pipe")
    XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
    do {
      _ = try await service.open(fifo)
      XCTFail("FIFO must not be read")
    } catch { XCTAssertEqual(error as? TextFileError, .notRegularFile) }
    do {
      _ = try await service.open(fixture.directory)
      XCTFail("Directory must not be read")
    } catch { XCTAssertEqual(error as? TextFileError, .notRegularFile) }
  }

  func testCancelledReadDoesNotReturnAFile() async throws {
    let fixture = try FileFixture()
    let url = fixture.directory.appending(path: "cancel.txt")
    try Data("original".utf8).write(to: url)
    let task = Task { try await TextFileService().open(url) }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Cancelled open must not commit a tab")
    } catch { XCTAssertTrue(error is CancellationError) }
  }

  func testSymbolicAndHardLinksIdentifyTheSameFileAndSaveKeepsSymlink() async throws {
    let fixture = try FileFixture()
    let url = fixture.directory.appending(path: "target.txt")
    let alias = fixture.directory.appending(path: "alias.txt")
    let hard = fixture.directory.appending(path: "hard.txt")
    try Data("original".utf8).write(to: url)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: url)
    try FileManager.default.linkItem(at: url, to: hard)
    let service = TextFileService()
    let opened = try await service.open(url)
    let linked = try await service.open(alias)
    let hardLinked = try await service.open(hard)
    XCTAssertEqual(opened.binding.identity, linked.binding.identity)
    XCTAssertEqual(opened.binding.identity, hardLinked.binding.identity)
    _ = try await service.save("updated", encoding: .utf8, to: alias, expected: linked.binding)
    XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path), url.path)
    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "updated")
  }
}

private final class FileFixture {
  let directory = FileManager.default.temporaryDirectory.appending(
    path: "NoteHushFileTests-\(UUID())")
  init() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  deinit { try? FileManager.default.removeItem(at: directory) }
}

private struct FailingTextPublisher: TextFilePublishing {
  func publish(_ data: Data, to url: URL) throws { throw TextFileError.unavailable }
}
