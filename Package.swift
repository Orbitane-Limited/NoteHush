// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "NoteHushCore",
  platforms: [.macOS(.v14)],
  products: [.library(name: "NoteHushCore", targets: ["NoteHushCore"])],
  targets: [
    .target(name: "NoteHushCore"),
    .executableTarget(
      name: "RecoveryCrashHarness", dependencies: ["NoteHushCore"],
      path: "Tests/RecoveryCrashHarness"),
    .testTarget(name: "NoteHushCoreTests", dependencies: ["NoteHushCore"]),
  ]
)
