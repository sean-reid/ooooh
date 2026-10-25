import Design
import Foundation

@MainActor
func run() throws {
  let arguments = CommandLine.arguments.dropFirst()
  let path = arguments.first ?? "App/Resources/Assets.xcassets/AppIcon.appiconset"
  let written = try IconRenderer.write(to: URL(fileURLWithPath: path))
  for url in written { print(url.path) }
}

try MainActor.assumeIsolated { try run() }
