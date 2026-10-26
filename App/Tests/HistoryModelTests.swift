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

  @Test func loadTakesOnePageAndLoadMoreAppendsTheRestOnce() async throws {
    let store = try SessionStore(configuration: .inMemory)
    let total = HistoryModel.page + 10
    try await Self.seed(store, count: total)
    let model = HistoryModel(store: store)
    #expect(!model.loaded)
    #expect(model.rows.isEmpty)

    await model.load()
    #expect(model.loaded)
    #expect(model.rows.count == HistoryModel.page)
    #expect(model.rows.first?.title == "Session \(total - 1)")
    #expect(model.rows.last?.title == "Session 10")

    await model.loadMore()
    #expect(model.rows.count == total)
    #expect(Set(model.rows.map(\.id)).count == total)
    #expect(model.rows.map(\.title) == (0..<total).reversed().map { "Session \($0)" })

    await model.loadMore()
    #expect(model.rows.count == total)
  }

  @Test func aSearchNarrowsTheRowsAndClearingItBringsThemBack() async throws {
    let store = try SessionStore(configuration: .inMemory)
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    for (index, (title, line)) in [
      ("Garden", "the garden needs a fence"), ("Kitchen", "the kitchen tap drips"),
      ("Attic", "the attic holds a zebrawood chest"),
    ].enumerated() {
      try await store.save(
        result: await Self.result(lines: [line]), notes: nil, title: title,
        startedAt: base.addingTimeInterval(Double(index) * 60))
    }
    let model = HistoryModel(store: store)
    await model.load()
    #expect(model.rows.map(\.title) == ["Attic", "Kitchen", "Garden"])

    model.query = "Zebrawood"
    await model.search()
    #expect(model.rows.map(\.title) == ["Attic"])
    await model.loadMore()
    #expect(model.rows.map(\.title) == ["Attic"])

    model.query = "the"
    await model.search()
    #expect(model.rows.map(\.title) == ["Attic", "Kitchen", "Garden"])

    model.query = "greenhouse"
    await model.search()
    #expect(model.rows.isEmpty)
    #expect(model.loaded)

    model.query = "   "
    await model.search()
    #expect(model.rows.map(\.title) == ["Attic", "Kitchen", "Garden"])

    model.query = ""
    await model.search()
    #expect(model.rows.map(\.title) == ["Attic", "Kitchen", "Garden"])
  }

  @Test func deletingTwoRowsRemovesThemFromTheStoreAndTheList() async throws {
    let store = try SessionStore(configuration: .inMemory)
    try await Self.seed(store, count: 4)
    let model = HistoryModel(store: store)
    await model.load()
    let kept = model.rows[1].id

    await model.delete(at: [0, 2])
    #expect(model.rows.map(\.title) == ["Session 2", "Session 0"])
    #expect(model.failure == nil)
    #expect(try await store.sessionCount() == 2)
    #expect(try await store.sessions().map(\.id) == model.rows.map(\.id))
    #expect(model.rows.first?.id == kept)
  }

  /// `count` sessions a minute apart, titled by index, oldest first.
  static func seed(_ store: SessionStore, count: Int) async throws {
    let result = await result(lines: ["the garden needs a fence"])
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    for index in 0..<count {
      try await store.save(
        result: result, notes: nil, title: "Session \(index)",
        startedAt: base.addingTimeInterval(Double(index) * 60))
    }
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
