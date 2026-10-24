// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "NoteHushCore",
  platforms: [.macOS(.v14)],
  products: [.library(name: "NoteHushCore", targets: ["NoteHushCore"])],
  targets: [
    .target(name: "NoteHushCore"),
    .target(
      name: "NativeFixtureSupport", dependencies: ["NoteHushCore"],
      path: "Tests/NativeFixtureSupport"),
    .executableTarget(
      name: "RecoveryCrashHarness", dependencies: ["NoteHushCore"],
      path: "Tests/RecoveryCrashHarness"),
    .executableTarget(
      name: "ColdLaunchHarness", dependencies: ["NoteHushCore", "NativeFixtureSupport"],
      path: "Tests/ColdLaunchHarness"),
    .executableTarget(
      name: "PerformanceFixtureHarness", dependencies: ["NoteHushCore"],
      path: "Tests/PerformanceFixtureHarness"),
    .executableTarget(
      name: "LargeFileOpenHarness", dependencies: ["NoteHushCore", "NativeFixtureSupport"],
      path: "Tests/LargeFileOpenHarness"),
    .executableTarget(
      name: "TextMetricsBenchmark", dependencies: ["NoteHushCore"],
      path: "Tests/TextMetricsBenchmark"),
    .executableTarget(
      name: "RecoveryBenchmark", dependencies: ["NoteHushCore"],
      path: "Tests/RecoveryBenchmark"),
    .testTarget(name: "NoteHushCoreTests", dependencies: ["NoteHushCore"]),
    .testTarget(name: "NativeFixtureSupportTests", dependencies: ["NativeFixtureSupport"]),
  ]
)
