import Foundation
import Notes
import Session
import Testing
import Transcription

@testable import Persistence
@testable import Settings

/// Serialized because the write tests share the one export directory.
@Suite(.serialized) struct ExportArchiveTests {
  static let exportedAt = Date(timeIntervalSince1970: 1_792_900_000)
  static let utc = TimeZone(identifier: "UTC")!

  @Test func aNewExportReplacesTheLastOneAndRemoveExportsClearsIt() async throws {
    let store = try SessionStore(configuration: .inMemory)
    let first = try await ExportFile(store: store).write(exportedAt: Self.exportedAt)
    let second = try await ExportFile(store: store).write(exportedAt: Self.exportedAt + 86_400)
    #expect(first.deletingLastPathComponent() == ExportFile.directory)
    let day = ExportArchive.dayFormatter(.current).string(from: Self.exportedAt + 86_400)
    #expect(second.lastPathComponent == "ooooh export \(day).zip")
    #expect(!FileManager.default.fileExists(atPath: first.path))
    #expect(FileManager.default.fileExists(atPath: second.path))

    ExportFile.removeExports()
    #expect(!FileManager.default.fileExists(atPath: ExportFile.directory.path))
  }

  @Test func crc32MatchesTheCheckValue() {
    #expect(ZipWriter.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    #expect(ZipWriter.crc32(Data()) == 0)
  }

  @Test func filesAreNamedByDayAndTitleWithCountersForRepeats() {
    let documents = [
      MarkdownDocument(filename: "2026-10-24-091500-rent.md", contents: "# Rent: or buy?\n\nbody"),
      MarkdownDocument(filename: "2026-10-24-183000-rent.md", contents: "# Rent: or buy?\n"),
      MarkdownDocument(filename: "2026-10-25-070000.md", contents: "# \n"),
      MarkdownDocument(filename: "odd.md", contents: "no heading"),
    ]
    let archive = ExportArchive(
      documents: documents, exportedAt: Self.exportedAt, timeZone: Self.utc)
    #expect(
      archive.files.map(\.name) == [
        "README.md", "2026-10-24 Rent or buy.md", "2026-10-24 Rent or buy 2.md",
        "2026-10-25 Untitled.md", "undated no heading.md",
      ])
    #expect(archive.filename == "ooooh export 2026-10-25.zip")
    #expect(archive.files[0].contents.contains("Exported from the ooooh app on October 25, 2026."))
    #expect(archive.files[0].contents.contains("4 sessions"))
  }

  @Test func eachFileEndsWithTheStampedTranscript() async throws {
    let store = try SessionStore(configuration: .inMemory)
    let base = Date(timeIntervalSince1970: 1_792_800_000)
    try await store.save(
      result: await Self.result(lines: ["the garden needs a fence", "and a gate"]),
      notes: SessionNotes(
        title: "Fence for the garden",
        actions: [NoteItem(id: "a1", text: "Price fencing")]),
      title: "", startedAt: base)
    try await store.save(
      result: await Self.result(lines: ["second pass"]), notes: nil, title: "Untitled pass",
      startedAt: base + 86_400)

    let archive = ExportArchive(
      documents: try await store.exportMarkdown(timeZone: Self.utc), exportedAt: Self.exportedAt,
      timeZone: Self.utc)
    #expect(
      archive.files.map(\.name) == [
        "README.md", "2026-10-24 Fence for the garden.md", "2026-10-25 Untitled pass.md",
      ])
    #expect(
      archive.files[1].contents.hasSuffix(
        "## Actions\n\n- Price fencing\n\n## Transcript\n\n"
          + "0:00 the garden needs a fence\n0:05 and a gate\n"))
    #expect(
      archive.files[2].contents
        == "# Untitled pass\n\nOctober 25, 2026\n\n## Transcript\n\n0:00 second pass\n")
  }

  #if os(macOS)
    @Test func theZipFromARealStoreUnzipsWithTheExpectedFiles() async throws {
      let store = try SessionStore(configuration: .inMemory)
      let base = Date(timeIntervalSince1970: 1_792_800_000)
      try await store.save(
        result: await Self.result(lines: ["the garden needs a fence"]),
        notes: SessionNotes(
          title: "Fence for the garden",
          actions: [NoteItem(id: "a1", text: "Price fencing")]),
        title: "", startedAt: base)
      try await store.save(
        result: await Self.result(lines: ["second pass"]), notes: nil, title: "Untitled pass",
        startedAt: base + 86_400)

      let url = try await ExportFile(store: store).write(exportedAt: Self.exportedAt)
      defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

      let test = try run("/usr/bin/unzip", ["-t", url.path])
      #expect(test.status == 0, "\(test.output)")
      let list = try run("/usr/bin/unzip", ["-Z1", url.path])
      let names = list.output.split(separator: "\n").map(String.init)
      let day = ExportArchive.dayFormatter(.current)
      #expect(
        names == [
          "README.md", "\(day.string(from: base)) Fence for the garden.md",
          "\(day.string(from: base + 86_400)) Untitled pass.md",
        ])

      let markdown = try #require(try await store.exportMarkdown().first).contents
      let extracted = try run("/usr/bin/unzip", ["-p", url.path, names[1]])
      #expect(extracted.output == markdown)
      #expect(markdown.contains("- Price fencing"))
    }

    private func run(_ tool: String, _ arguments: [String]) throws -> (
      status: Int32, output: String
    ) {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: tool)
      process.arguments = arguments
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = pipe
      try process.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
  #endif

  static func result(lines: [String]) async -> SessionResult {
    let segments = lines.enumerated().map { index, text in
      Segment(text: text, start: Double(index) * 5, end: Double(index) * 5 + 4, isFinal: true)
    }
    return await FixtureDriver.run(
      fixture: FixtureTranscriber.Fixture(segments: segments), config: .initial,
      dependencies: .init(
        decisions: SilentDecisionProvider(), compactor: PassthroughCompactor(),
        phraser: TemplatePhraser()))
  }
}
