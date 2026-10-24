import AppKit
import NativeFixtureSupport

/// Numeric/static protocol records. Generated file paths and bookmark bytes are
/// deliberately excluded from the journal that may accompany a public report.
final class OpenEvidenceLog {
  private let handle: FileHandle
  private var closed = false

  init(url: URL) throws {
    let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw OpenFailure.evidenceWrite }
    handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
  }

  func append(_ record: some Encodable) throws {
    guard !closed else { throw OpenFailure.evidenceWrite }
    var data = try JSONEncoder().encode(record)
    data.append(0x0A)
    try handle.write(contentsOf: data)
    try handle.synchronize()
  }

  func close() throws {
    guard !closed else { return }
    try handle.synchronize()
    try handle.close()
    closed = true
  }
}

struct OpenHeader: Encodable {
  let kind = "header"
  let schema = 1
  let unit = "nanoseconds"
  let boundary = "fileOpenRequestToCompleteDurableCheckpoint"
  let observationsPerWorkload: Int
  let bytesPerFile: Int
  let observationBoundNanoseconds: UInt64 = 10_000_000_000
  let normalQuitBoundSeconds = 20
  let workloads: [LargeOpenWorkload]

  init(observationsPerWorkload: Int, bytesPerFile: Int, workloads: [LargeOpenWorkload]) {
    self.observationsPerWorkload = observationsPerWorkload
    self.bytesPerFile = bytesPerFile
    self.workloads = workloads
  }
}

struct OpenAttempt: Encodable {
  let kind = "attempt"
  let workload: LargeOpenWorkload
  let index: Int
  let workspace: UUID
}

struct OpenProcess: Encodable {
  let kind = "process"
  let workload: LargeOpenWorkload
  let index: Int
  let pid: Int32
  let exactApplicationIdentity = true
}

struct OpenObservation: Encodable {
  let kind = "observation"
  let workload: LargeOpenWorkload
  let index: Int
  let requestToCheckpointNanoseconds: UInt64
  let launchServicesReturnNanoseconds: UInt64
  let withinObservationBound: Bool
}

struct OpenTimeout: Encodable {
  let kind = "timeout"
  let workload: LargeOpenWorkload
  let index: Int
  let elapsedNanoseconds: UInt64
  let observationBoundNanoseconds: UInt64 = 10_000_000_000
  let recoveryVerified = false
}

struct OpenProfile: Encodable {
  let kind = "profile"
  let workload: LargeOpenWorkload
  let index: Int
  let pid: Int32
  let sampleDurationSeconds = 2
  let status: String
  let exitCode: Int32?
  let outputBytes: Int?
  let outputSHA256: String?
}

struct OpenVerification: Encodable {
  let kind = "verification"
  let workload: LargeOpenWorkload
  let index: Int
  let activeDuringObservation = true
  let normalQuit = true
  let completeRecovery = true
  let unchangedSourceBytes = true
  let fileBindingAndIdentity = true
  let selectionAndViewport = true
  let tabOrderAndWindow = true
}

struct OpenFinish: Encodable {
  let kind = "finish"
  let verifiedObservations: Int

  init(verifiedObservations: Int) { self.verifiedObservations = verifiedObservations }
}

struct OpenRunFailure: Encodable {
  let kind = "failure"
  let code: String
}

struct OpenManifest: Encodable {
  let version = 1
  let applicationURL: URL
  let environment: OpenEnvironment
  let fixtures: [OpenFixture]
}

struct OpenFixture: Encodable { let name: String }

struct OpenEnvironment: Encodable {
  let capturedAt: Date
  let lowPowerMode: Bool
  let thermalState: Int
  let screens: [OpenScreen]
}

struct OpenScreen: Encodable {
  let widthPoints: Double
  let heightPoints: Double
  let scale: Double
}
