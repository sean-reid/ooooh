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
    .library(name: "Persistence", targets: ["Persistence"]),
    .library(name: "Billing", targets: ["Billing"]),
    .library(name: "Settings", targets: ["Settings"]),
    .executable(name: "eval", targets: ["eval"]),
    .executable(name: "render-icon", targets: ["render-icon"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.7")
  ],
  targets: [
    .target(name: "Design", resources: [.copy("Fonts")]),
    .target(name: "State"),
    .target(name: "Governor", dependencies: ["State"]),
    .target(name: "Notes", dependencies: ["State", "Transcription", "Design"]),
    .target(name: "Transcription"),
    .target(name: "Audio"),
    .target(
      name: "Proxy", dependencies: ["State", "Governor", "Session", "Transcription", "Notes"]),
    .target(name: "Session", dependencies: ["State", "Governor", "Transcription"]),
    .target(name: "Persistence", dependencies: ["State", "Notes", "Session", "Transcription"]),
    .target(name: "Billing", dependencies: ["Design", "Proxy"]),
    .target(name: "Settings", dependencies: ["Persistence", "Design", "Notes"]),
    .executableTarget(name: "eval", dependencies: ["Session", "Proxy"]),
    .executableTarget(name: "render-icon", dependencies: ["Design"]),
    .testTarget(
      name: "DesignTests",
      dependencies: [
        "Design", .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ], exclude: ["__Snapshots__"], resources: [.copy("Fixtures")]),
    .testTarget(name: "StateTests", dependencies: ["State"]),
    .testTarget(name: "GovernorTests", dependencies: ["Governor"]),
    .testTarget(name: "NotesTests", dependencies: ["Notes"]),
    .testTarget(
      name: "NotesSnapshotTests",
      dependencies: [
        "Notes", .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ], exclude: ["__Snapshots__"]),
    .testTarget(
      name: "SessionTests", dependencies: ["Session"], resources: [.copy("Fixtures")]),
    .testTarget(name: "TranscriptionTests", dependencies: ["Transcription"]),
    .testTarget(name: "AudioTests", dependencies: ["Audio"], resources: [.copy("Fixtures")]),
    .testTarget(name: "ProxyTests", dependencies: ["Proxy"], resources: [.copy("Fixtures")]),
    .testTarget(
      name: "PersistenceTests", dependencies: ["Persistence"], resources: [.copy("Fixtures")]),
    .testTarget(name: "SettingsTests", dependencies: ["Settings", "Session"]),
    .testTarget(
      name: "SettingsSnapshotTests",
      dependencies: [
        "Settings", "Persistence",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ], exclude: ["__Snapshots__"]),
  ]
)
