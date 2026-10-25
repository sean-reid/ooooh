// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "ooooh",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "Design", targets: ["Design"]),
    .library(name: "State", targets: ["State"]),
    .library(name: "Governor", targets: ["Governor"]),
    .library(name: "Notes", targets: ["Notes"]),
    .library(name: "Transcription", targets: ["Transcription"]),
    .library(name: "Audio", targets: ["Audio"]),
    .library(name: "Proxy", targets: ["Proxy"]),
    .library(name: "Session", targets: ["Session"]),
    .executable(name: "eval", targets: ["eval"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.7")
  ],
  targets: [
    .target(name: "Design", resources: [.copy("Fonts")]),
    .target(name: "State"),
    .target(name: "Governor", dependencies: ["State"]),
    .target(name: "Notes", dependencies: ["State"]),
    .target(name: "Transcription"),
    .target(name: "Audio"),
    .target(name: "Proxy", dependencies: ["State", "Governor", "Session", "Transcription"]),
    .target(name: "Session", dependencies: ["State", "Governor", "Transcription"]),
    .executableTarget(name: "eval", dependencies: ["Session"]),
    .testTarget(
      name: "DesignTests",
      dependencies: [
        "Design", .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ]),
    .testTarget(name: "StateTests", dependencies: ["State"]),
    .testTarget(name: "GovernorTests", dependencies: ["Governor"]),
    .testTarget(name: "NotesTests", dependencies: ["Notes"]),
    .testTarget(
      name: "SessionTests", dependencies: ["Session"], resources: [.copy("Fixtures")]),
    .testTarget(name: "TranscriptionTests", dependencies: ["Transcription"]),
    .testTarget(name: "ProxyTests", dependencies: ["Proxy"], resources: [.copy("Fixtures")]),
  ]
)
