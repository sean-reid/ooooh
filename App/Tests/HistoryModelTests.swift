import Foundation
import Governor
import Notes
import Persistence
import Session
import SwiftData
import Testing
import Transcription

@testable import ooooh

@MainActor
@Suite struct HistoryModelTests {
  @Test func aRefusedDeleteKeepsTheRowAndSaysSo() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("history-\(UUID().uuidString).store")
    let writable = try Self.store(at: url, allowsSave: true)
    let result = await Self.result(lines: ["the garden needs a fence"])
    try await writable.save(result: result, notes: nil, title: "Garden")
    try await writable.save(result: result, notes: nil, title: "Fence", startedAt: .now + 60)

    let model = HistoryModel(store: try Self.store(at: url, allowsSave: false))
    await model.load()
    #expect(model.rows.map(\.title) == ["Fence", "Garden"])
    #expect(model.failure == nil)

    await model.delete(at: [0])
    #expect(model.rows.map(\.title) == ["Fence", "Garden"])
    #expect(model.failure == HistoryModel.deleteFailedLine)
    #expect(try await writable.sessionCount() == 2)
  }

  @Test func aDeleteThatSucceedsRemovesTheRow() async throws {
    let store = try SessionStore(configuration: .inMemory)
    let result = await Self.result(lines: ["the garden needs a fence"])
    try await store.save(result: result, notes: nil, title: "Garden")
    try await store.save(result: result, notes: nil, title: "Fence", startedAt: .now + 60)
    let model = HistoryModel(store: store)
    await model.load()

    await model.delete(at: [0])
    #expect(model.rows.map(\.title) == ["Garden"])
    #expect(model.failure == nil)
    #expect(try await store.sessionCount() == 1)
  }

  static func store(at url: URL, allowsSave: Bool) throws -> SessionStore {
    let configuration = ModelConfiguration(
      schema: PersistenceContainer.schema, url: url, allowsSave: allowsSave, cloudKitDatabase: .none
    )
    return SessionStore(
      modelContainer: try ModelContainer(
        for: PersistenceContainer.schema, configurations: [configuration]))
  }

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
