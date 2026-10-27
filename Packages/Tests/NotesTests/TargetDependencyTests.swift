import Foundation
import Testing

/// Reads Package.swift as text so a dependency added to the model target fails here, not in a
/// link time surprise for Proxy or Persistence.
@Suite struct TargetDependencyTests {
  static let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  let graph: [String: [String]]

  init() throws {
    let manifest = try String(contentsOf: Self.packageRoot.appending(path: "Package.swift"))
    graph = Self.targets(in: manifest)
  }

  @Test func notesIsModelOnly() {
    #expect(graph["Notes"] == ["State", "Transcription"])
  }

  @Test(arguments: ["Notes", "Proxy", "Persistence", "eval"])
  func linksNoUI(target: String) {
    let linked = closure(of: target)
    #expect(!linked.contains("Design"), "\(target) links Design through \(linked.sorted())")
    #expect(!linked.contains("NotesUI"), "\(target) links NotesUI through \(linked.sorted())")
  }

  @Test func notesSourcesImportNoUI() throws {
    let sources = Self.packageRoot.appending(path: "Sources/Notes")
    let files = try FileManager.default.contentsOfDirectory(atPath: sources.path)
      .filter { $0.hasSuffix(".swift") }
    #expect(!files.isEmpty)
    for file in files {
      let text = try String(contentsOf: sources.appending(path: file))
      let imports = text.split(separator: "\n").filter { $0.hasPrefix("import ") }
      #expect(!imports.contains("import SwiftUI"), "\(file)")
      #expect(!imports.contains("import Design"), "\(file)")
    }
  }

  private func closure(of target: String) -> Set<String> {
    var seen = Set<String>()
    var stack = [target]
    while let next = stack.popLast() {
      guard seen.insert(next).inserted else { continue }
      stack += graph[next] ?? []
    }
    seen.remove(target)
    return seen
  }

  /// Every `.target` and `.executableTarget` with the quoted names in its dependency list.
  static func targets(in manifest: String) -> [String: [String]] {
    let pattern =
      #"\.(?:executableTarget|target)\(\s*name: "(\w+)"(?:,\s*dependencies: \[([^\]]*)\])?"#
    let regex = try! Regex(pattern)
    var graph: [String: [String]] = [:]
    for match in manifest.matches(of: regex) {
      let name = String(match.output[1].substring!)
      let list = match.output[2].substring.map(String.init) ?? ""
      graph[name] = list.matches(of: /"(\w+)"/).map { String($0.output.1) }
    }
    return graph
  }
}
