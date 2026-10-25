import Foundation
import Notes
import Testing

@testable import Persistence

@Suite struct MigrationTests {
  /// `Fixtures/before-summary.store` holds two sessions from a schema with no
  /// `StoredSession.summary`: the pricing fixture with its notes, then Garden with none.
  @Test func aStoreWithoutTheSummaryColumnOpensAndTakesOne() async throws {
    let fixture = try #require(
      Bundle.module.url(
        forResource: "before-summary", withExtension: "store", subdirectory: "Fixtures"))
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ooooh-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("sessions.store")
    try FileManager.default.copyItem(at: fixture, to: url)

    let store = try Support.store(at: url)
    let sessions = try await store.sessions()
    #expect(sessions.map(\.title) == ["Garden", "Pricing and the free tier"])
    #expect(sessions.map(\.summary) == [nil, nil])
    #expect(try await store.counts() == .init(sessions: 2, segments: 19, items: 6, threads: 2))
    #expect(try await store.notes(for: sessions[1].id) == Support.notes)
    #expect(try await store.notes(for: sessions[0].id) == nil)

    let notes = SessionNotes(title: "Garden", summary: "A fence first, then the gate.")
    try await store.attachNotes(notes, to: sessions[0].id)
    let reopened = try Support.store(at: url)
    #expect(try await reopened.notes(for: sessions[0].id) == notes)
    #expect(try await reopened.search("fence first").map(\.title) == ["Garden"])
  }
}
