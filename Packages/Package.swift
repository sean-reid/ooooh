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
  ],
  targets: [
    .target(name: "Design"),
    .target(name: "State"),
    .target(name: "Governor", dependencies: ["State"]),
    .target(name: "Notes", dependencies: ["State"]),
    .target(name: "Transcription"),
    .target(name: "Audio"),
    .target(name: "Proxy", dependencies: ["State", "Governor"]),
    .testTarget(name: "StateTests", dependencies: ["State"]),
    .testTarget(name: "GovernorTests", dependencies: ["Governor"]),
    .testTarget(name: "NotesTests", dependencies: ["Notes"]),
  ]
)
