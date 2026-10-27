import Foundation
import Notes
import Testing
import Transcription

@testable import Persistence

@Suite struct SessionStoreTests {
  @Test func savesTheFixtureAndReadsItBack() async throws {
    let store = try Support.store()
    let result = try await Support.shortResult()
    let started = Date(timeIntervalSince1970: 1_792_900_000)
    let id = try await store.save(
      result: result, notes: Support.notes, title: "Placeholder", startedAt: started)

    let detail = try #require(try await store.detail(id))
    #expect(detail.summary.title == "Pricing and the free tier")
    #expect(detail.summary.startedAt == started)
    #expect(detail.summary.duration >= 87.8)
    #expect(detail.endedAt == started.addingTimeInterval(detail.summary.duration))
    #expect(detail.transcript == result.transcript)
    #expect(detail.state == result.state)
    #expect(detail.modeAtEnd == result.state.mode)
    #expect(detail.notes == Support.notes)
    #expect(detail.summary.summary == nil)
    #expect(detail.summary.openThreadCount == 2)
    #expect(detail.audioPath == nil)
  }

  @Test func theDurationIsTheEndItWasGivenNotTheLastSpeech() async throws {
    let store = try Support.store()
    let result = try await Support.shortResult()
    let started = Date(timeIntervalSince1970: 1_792_900_000)
    let ended = started.addingTimeInterval(12 * 60)
    let id = try await store.save(
      result: result, notes: nil, title: "", startedAt: started, endedAt: ended)

    let detail = try #require(try await store.detail(id))
    #expect(SessionStore.duration(of: result) == 87.8)
    #expect(detail.summary.duration == 720)
    #expect(detail.endedAt == ended)
    #expect(try await store.sessions().map(\.duration) == [720])
  }

  @Test func aSummaryWithNoItemsRoundTrips() async throws {
    let store = try Support.store()
    let notes = SessionNotes(
      title: "A quick one", summary: "Two minutes on where the hummingbird feeder goes.")
    let id = try await store.save(result: try await Support.shortResult(), notes: notes, title: "")

    #expect(try await store.notes(for: id) == notes)
    let detail = try #require(try await store.detail(id))
    #expect(detail.notes == notes)
    #expect(detail.items.isEmpty)
    #expect(try await store.sessions().map(\.summary) == [notes.summary])
    #expect(try await store.search("Hummingbird").map(\.id) == [id])
  }

  @Test func regeneratedNotesReplaceTheSummary() async throws {
    let store = try Support.store()
    let id = try await store.save(
      result: try await Support.shortResult(), notes: Support.notes, title: "")
    #expect(try await store.sessions().map(\.summary) == [nil])

    var notes = Support.notes
    notes.summary = "Pricing in one paragraph."
    try await store.attachNotes(notes, to: id)
    #expect(try await store.notes(for: id)?.summary == "Pricing in one paragraph.")
    #expect(try await store.search("paragraph").map(\.id) == [id])

    try await store.attachNotes(Support.notes, to: id)
    #expect(try await store.notes(for: id) == Support.notes)
    #expect(try await store.search("paragraph").isEmpty)
  }

  @Test func notesAttachedLaterReplaceOnlyUneditedItems() async throws {
    let store = try Support.store()
    let result = try await Support.shortResult()
    let id = try await store.save(result: result, notes: nil, title: "Untitled")
    #expect(try await store.notes(for: id) == nil)

    try await store.attachNotes(Support.notes, to: id)
    let question = try #require(
      try await store.items(in: id).first { $0.section == .questions })
    try await store.editItem(question.id, text: "Will people pay seven dollars a month")

    var regenerated = Support.notes
    regenerated.questions = [NoteItem(id: "q1", text: "Will anyone pay")]
    regenerated.ideas = [NoteItem(id: "i2", text: "Free sessions can run long")]
    regenerated.openThreads = [NoteItem(id: "t1", text: "What the free tier is for")]
    try await store.attachNotes(regenerated, to: id)

    let notes = try #require(try await store.notes(for: id))
    #expect(notes.questions.map(\.text) == ["Will people pay seven dollars a month"])
    #expect(notes.questions[0].edited)
    #expect(notes.ideas.map(\.id) == ["i2"])
    #expect(notes.openThreads.map(\.id) == ["t1"])
    #expect(try await store.openThreads(limit: 10).map(\.noteItemID) == ["t1"])
  }

  @Test func historyIsNewestFirstWithOpenThreadCounts() async throws {
    let store = try Support.store()
    let result = try await Support.shortResult()
    let base = Date(timeIntervalSince1970: 1_792_900_000)
    let older = try await store.save(
      result: result, notes: Support.notes, title: "", startedAt: base)
    let newer = try await store.save(
      result: result, notes: SessionNotes(title: "Second"), title: "", startedAt: base + 3600)
    let newest = try await store.save(
      result: result, notes: nil, title: "Third", startedAt: base + 7200)

    let all = try await store.sessions()
    #expect(all.map(\.id) == [newest, newer, older])
    #expect(all.map(\.openThreadCount) == [0, 0, 2])
    #expect(all.map(\.title) == ["Third", "Second", "Pricing and the free tier"])
    #expect(try await store.sessions(limit: 1, offset: 1).map(\.id) == [newer])
  }

  @Test func sessionCountIsTheRowCount() async throws {
    let store = try Support.store()
    #expect(try await store.sessionCount() == 0)
    let result = try await Support.shortResult()
    for _ in 0..<4 {
      try await store.save(result: result, notes: nil, title: "")
    }
    #expect(try await store.sessionCount() == 4)
    #expect(try await store.sessionCount() == store.counts().sessions)
  }

  @Test func openThreadsAreTheNewestThreeOfTen() async throws {
    let store = try Support.store()
    let result = try await Support.shortResult()
    let base = Date(timeIntervalSince1970: 1_792_900_000)
    var ids: [UUID] = []
    for index in 0..<10 {
      let notes = SessionNotes(
        title: "Session \(index)",
        openThreads: [
          NoteItem(id: "first", text: "First thread of \(index)"),
          NoteItem(id: "second", text: "Second thread of \(index)"),
        ])
      // Saved out of order so the sort comes from the dates, not insertion.
      let at = base.addingTimeInterval(Double((index * 7) % 10) * 3600)
      ids.append(try await store.save(result: result, notes: notes, title: "", startedAt: at))
    }
    try await store.resolve(thread: try #require(try await store.openThreads(limit: 1).first).id)

    let offered = try await store.openThreads()
    #expect(
      offered.map(\.text) == ["Second thread of 7", "First thread of 4", "Second thread of 4"])
    #expect(offered.map(\.sessionID) == [ids[7], ids[4], ids[4]])
    #expect(offered.map(\.sessionStartedAt) == [base + 9 * 3600, base + 8 * 3600, base + 8 * 3600])
    #expect(try await store.openThreads(limit: 25).count == 19)
  }

  @Test func searchReturnsTheNewestPageOfMatches() async throws {
    let store = try Support.store()
    let base = Date(timeIntervalSince1970: 1_792_900_000)
    for index in 0..<8 {
      try await store.save(
        result: await Support.result(lines: ["the garden needs a fence \(index)"]), notes: nil,
        title: "Garden \(index)", startedAt: base.addingTimeInterval(Double(index) * 60))
    }
    let page = try await store.search("fence", limit: 3)
    #expect(page.map(\.title) == ["Garden 7", "Garden 6", "Garden 5"])
    #expect(try await store.search("fence").count == 8)
    #expect(try await store.search("fence", limit: 0).isEmpty)
  }

  @Test func searchFindsSegmentsAndItemsAndNotAbsentWords() async throws {
    let store = try Support.store()
    let result = try await Support.shortResult()
    let id = try await store.save(result: result, notes: Support.notes, title: "")
    let other = try await store.save(
      result: await Support.result(lines: ["the garden needs a fence", "and a gate"]),
      notes: SessionNotes(title: "Garden", actions: [NoteItem(id: "a1", text: "Price fencing")]),
      title: "", startedAt: Date(timeIntervalSince1970: 0))

    #expect(try await store.search("Comparables").map(\.id) == [id])
    #expect(try await store.search("twenty minutes").map(\.id) == [id])
    #expect(try await store.search("GATE").map(\.id) == [other])
    #expect(try await store.search("fencing").map(\.id) == [other])
    #expect(try await store.search("pricing").map(\.id) == [id])
    #expect(try await store.search("zebrawood").isEmpty)
    #expect(try await store.search("   ").isEmpty)
  }

  @Test func resolvingAThreadHidesItFromTheCarryover() async throws {
    let store = try Support.store()
    let result = try await Support.shortResult()
    let id = try await store.save(result: result, notes: Support.notes, title: "")
    let next = try await store.save(
      result: result, notes: nil, title: "Next", startedAt: .now + 60)

    let offered = try await store.openThreads(limit: 3)
    #expect(offered.map(\.noteItemID) == ["t1", "t2"])
    #expect(offered.allSatisfy { $0.sessionID == id })
    try await store.resolve(thread: offered[0].id, in: next)

    #expect(try await store.openThreads(limit: 3).map(\.noteItemID) == ["t2"])
    #expect(try await store.sessions().first { $0.id == id }?.openThreadCount == 1)
    let notes = try #require(try await store.notes(for: id))
    #expect(notes.openThreads.map(\.resolved) == [true, false])
    #expect(try await store.openThreads(limit: 0).isEmpty)
  }

  @Test func editingMarksTheItemEditedAndTouchesItsThread() async throws {
    let store = try Support.store()
    let id = try await store.save(
      result: try await Support.shortResult(), notes: Support.notes, title: "")
    let items = try await store.items(in: id)
    #expect(items.allSatisfy { !$0.item.edited })

    let decision = try #require(items.first { $0.section == .decisions })
    #expect(try await store.search("quarterly").isEmpty)
    try await store.editItem(decision.id, text: "Cap prompts at fifteen minutes, revisit quarterly")
    let thread = try #require(items.first { $0.section == .openThreads })
    try await store.editItem(thread.id, resolved: true)

    let after = try await store.items(in: id)
    let editedDecision = try #require(after.first { $0.id == decision.id })
    #expect(editedDecision.item.text == "Cap prompts at fifteen minutes, revisit quarterly")
    #expect(editedDecision.item.edited)
    #expect(after.filter(\.item.edited).count == 2)
    #expect(try await store.openThreads(limit: 5).map(\.noteItemID) == ["t2"])
    #expect(try await store.search("quarterly").map(\.id) == [id])
  }

  @Test func addingAndDeletingItems() async throws {
    let store = try Support.store()
    let id = try await store.save(
      result: try await Support.shortResult(), notes: Support.notes, title: "")
    let added = try await store.addItem("Ask three people this week", section: .actions, to: id)
    let addedThread = try await store.addItem("Annual pricing", section: .openThreads, to: id)

    var notes = try #require(try await store.notes(for: id))
    #expect(notes.actions.map(\.text) == ["Ask three people this week"])
    #expect(notes.actions[0].edited)
    #expect(notes.openThreads.map(\.text).last == "Annual pricing")
    #expect(try await store.openThreads(limit: 5).count == 3)

    try await store.deleteItem(added)
    try await store.deleteItem(addedThread)
    notes = try #require(try await store.notes(for: id))
    #expect(notes.actions.isEmpty)
    #expect(notes.openThreads.count == 2)
    #expect(try await store.openThreads(limit: 5).count == 2)
    await #expect(throws: StoreError.missingItem(added)) {
      try await store.editItem(added, text: "gone")
    }
  }

  @Test func deletingASessionRemovesItsRowsAndKeptAudio() async throws {
    let store = try Support.store()
    let result = try await Support.shortResult()
    let audio = FileManager.default.temporaryDirectory
      .appendingPathComponent("ooooh-\(UUID().uuidString).caf")
    try Data([0, 1, 2]).write(to: audio)
    let doomed = try await store.save(
      result: result, notes: Support.notes, title: "", audioPath: audio.path, keepAudio: true)
    let survivor = try await store.save(result: result, notes: Support.notes, title: "")
    #expect(try await store.detail(doomed)?.audioPath == audio.path)
    #expect(try await store.counts() == .init(sessions: 2, segments: 34, items: 12, threads: 4))

    try await store.delete(session: doomed)

    #expect(try await store.counts() == .init(sessions: 1, segments: 17, items: 6, threads: 2))
    #expect(try await store.sessions().map(\.id) == [survivor])
    #expect(try await store.detail(doomed) == nil)
    #expect(!FileManager.default.fileExists(atPath: audio.path))
    await #expect(throws: StoreError.missingSession(doomed)) {
      try await store.delete(session: doomed)
    }
  }

  @Test func deleteEverythingLeavesNoRows() async throws {
    let store = try Support.store()
    let result = try await Support.shortResult()
    for _ in 0..<3 {
      try await store.save(result: result, notes: Support.notes, title: "")
    }
    try await store.deleteEverything()
    #expect(try await store.counts() == .init(sessions: 0, segments: 0, items: 0, threads: 0))
    #expect(try await store.sessions().isEmpty)
    #expect(try await store.openThreads().isEmpty)
  }

  @Test func exportMatchesTheNotesMarkdown() async throws {
    let store = try Support.store()
    let result = try await Support.shortResult()
    let utc = TimeZone(identifier: "UTC")!
    let first = Date(timeIntervalSince1970: 1_792_900_000)
    try await store.save(result: result, notes: Support.notes, title: "", startedAt: first)
    try await store.save(
      result: result, notes: nil, title: "No notes yet", startedAt: first + 86_400)

    let documents = try await store.exportMarkdown(timeZone: utc)
    #expect(
      documents.map(\.filename) == [
        "2026-10-25-034640-pricing-and-the-free-tier.md", "2026-10-26-034640-no-notes-yet.md",
      ])
    let transcript = result.transcript.filter(\.isFinal)
    #expect(transcript.count == 17)
    #expect(
      documents[0].contents
        == Support.notes.markdown(date: first, timeZone: utc, transcript: transcript))
    #expect(
      documents[1].contents.hasPrefix(
        "# No notes yet\n\nOctober 26, 2026\n\n## Transcript\n\n"
          + "0:00 okay so the thing I keep coming back to is pricing\n0:05 like I know"))
    #expect(documents[1].contents.hasSuffix("\n1:26 okay I'm done for now\n"))
  }

  @Test func exportPutsTheSummaryUnderTheTitle() async throws {
    let store = try Support.store()
    let result = try await Support.shortResult()
    let utc = TimeZone(identifier: "UTC")!
    let first = Date(timeIntervalSince1970: 1_792_900_000)
    try await store.save(
      result: result,
      notes: SessionNotes(
        title: "A quick one", summary: "Two minutes on the feeder.",
        openThreads: [NoteItem(id: "t1", text: "Window or porch")]),
      title: "", startedAt: first)
    try await store.save(
      result: result, notes: SessionNotes(title: "Shorter", summary: "One thought, no list."),
      title: "", startedAt: first + 86_400)
    try await store.save(
      result: result, notes: Support.notes, title: "", startedAt: first + 172_800)

    let documents = try await store.exportMarkdown(timeZone: utc)
    #expect(
      documents.map(\.filename) == [
        "2026-10-25-034640-a-quick-one.md", "2026-10-26-034640-shorter.md",
        "2026-10-27-034640-pricing-and-the-free-tier.md",
      ])
    #expect(
      documents[0].contents.hasPrefix(
        """
        # A quick one

        October 25, 2026

        Two minutes on the feeder.

        ## Open threads

        - Window or porch

        ## Transcript

        0:00 okay so the thing I keep coming back to is pricing

        """))
    #expect(
      documents[1].contents.hasPrefix(
        "# Shorter\n\nOctober 26, 2026\n\nOne thought, no list.\n\n## Transcript\n"))
    #expect(
      documents[2].contents.hasPrefix(
        "# Pricing and the free tier\n\nOctober 27, 2026\n\n## Ideas\n"))
  }
}
