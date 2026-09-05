// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "NoteHushCore",
  platforms: [.macOS(.v14)],
  products: [.library(name: "NoteHushCore", targets: ["NoteHushCore"])],
  targets: [
    .target(name: "NoteHushCore"),
    .testTarget(name: "NoteHushCoreTests", dependencies: ["NoteHushCore"]),
  ]
)
