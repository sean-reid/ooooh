import Foundation
import Governor
import Notes
import Session
import SwiftData
import Transcription

@testable import Persistence

enum Support {
  /// The SessionTests fixture, run through the real loop with the silent provider.
  static func shortResult() async throws -> SessionResult {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("SessionTests/Fixtures/short.json")
    let fixture = try JSONDecoder().decode(
      FixtureTranscriber.Fixture.self, from: Data(contentsOf: url))
    return await result(fixture)
  }

  static func result(lines: [String]) async -> SessionResult {
    let segments = lines.enumerated().map { index, text in
      Segment(text: text, start: Double(index) * 5, end: Double(index) * 5 + 4, isFinal: true)
    }
    return await result(FixtureTranscriber.Fixture(segments: segments))
  }

  static func result(_ fixture: FixtureTranscriber.Fixture) async -> SessionResult {
    await FixtureDriver.run(
      fixture: fixture, config: .initial,
      dependencies: .init(
        decisions: SilentDecisionProvider(), compactor: PassthroughCompactor(),
        phraser: TemplatePhraser()))
  }

  static let notes = SessionNotes(
    title: "Pricing and the free tier",
    ideas: [
      NoteItem(
        id: "i1", text: "Cap the expensive part, not sessions", span: .init(start: 56, end: 60.2))
    ],
    decisions: [
      NoteItem(id: "d1", text: "Cap prompts at twenty minutes", span: .init(start: 72, end: 80.6))
    ],
    questions: [NoteItem(id: "q1", text: "Will people pay seven dollars")],
    openThreads: [
      NoteItem(id: "t1", text: "What the free tier is for"),
      NoteItem(id: "t2", text: "Whether the comparables mean underpricing"),
    ],
    quotes: [NoteItem(id: "x1", text: "listening is cheap, prompts cost money")])

  static func store() throws -> SessionStore {
    try SessionStore(configuration: .inMemory)
  }

  static func store(at url: URL) throws -> SessionStore {
    let configuration = ModelConfiguration(
      schema: PersistenceContainer.schema, url: url, cloudKitDatabase: .none)
    return SessionStore(
      modelContainer: try ModelContainer(
        for: PersistenceContainer.schema, configurations: [configuration]))
  }
}
