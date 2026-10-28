import Foundation
import Notes
import SwiftData
import TestSupport
import Testing

@testable import Persistence

/// `Fixtures/before-summary.store` holds two sessions from a schema with no
/// `StoredSession.summary` and no `StoredThread.sessionStartedAt`: the pricing fixture
/// with its notes and two open threads, then Garden with none.
@Suite struct MigrationTests {
  @Test func aStoreWithoutTheSummaryColumnOpensAndTakesOne() async throws {
    let directory = try Self.scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = try Self.copyFixture(into: directory)

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

  @Test func threadsFromAStoreWithoutTheSortKeyTakeTheirSessionDate() async throws {
    let directory = try Self.scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = try Self.copyFixture(into: directory)

    let store = try Support.store(at: url)
    let pricing = try await store.sessions()[1]
    #expect(try await store.threadSortKeys() == [pricing.startedAt, pricing.startedAt])

    let earlier = pricing.startedAt.addingTimeInterval(-86_400)
    let notes = SessionNotes(
      title: "Earlier", openThreads: [NoteItem(id: "t9", text: "Whether to move the launch")])
    try await store.save(
      result: await Support.shortResult(), notes: notes, title: "", startedAt: earlier)
    let offered = try await store.openThreads(limit: 5)
    #expect(offered.map(\.noteItemID) == ["t1", "t2", "t9"])
    #expect(offered.map(\.sessionStartedAt) == [pricing.startedAt, pricing.startedAt, earlier])
  }

  static func scratchDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ooooh-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  static func copyFixture(into directory: URL) throws -> URL {
    let url = directory.appendingPathComponent("sessions.store")
    try FileManager.default.copyItem(
      at: try Bundle.module.fixtureURL("before-summary.store"), to: url)
    return url
  }
}

extension SessionStore {
  fileprivate func threadSortKeys() throws -> [Date] {
    try modelContext.fetch(FetchDescriptor<StoredThread>(sortBy: [SortDescriptor(\.order)]))
      .map(\.sessionStartedAt)
  }
}
