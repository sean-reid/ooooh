import Foundation
import Notes
import Persistence
import SwiftData
import Testing

@testable import ooooh

/// The editor over a real store: every hook lands in the store and comes back through `notes`.
@MainActor
@Suite struct NotesEditorTests {
  static let notes = SessionNotes(
    title: "Pricing and the free tier",
    ideas: [NoteItem(id: "cap-cost", text: "Cap the expensive part, not sessions")],
    decisions: [NoteItem(id: "cap-prompts", text: "Cap prompts at twenty minutes")],
    openThreads: [
      NoteItem(id: "free-tier-purpose", text: "What the free tier is for"),
      NoteItem(id: "comparables", text: "Whether the comparables mean underpricing"),
    ])

  @Test func editDeleteAddAndResolveReachTheStoreInOrder() async throws {
    let store = try SessionStore(configuration: .inMemory)
    let editor = try await Self.editor(over: store)
    let hooks = editor.hooks

    hooks.edit(.decisions, editor.notes.decisions[0], "Cap prompts at fifteen minutes")
    #expect(editor.notes.decisions.map(\.text) == ["Cap prompts at fifteen minutes"])
    hooks.delete(.ideas, editor.notes.ideas[0])
    #expect(editor.notes.ideas.isEmpty)
    hooks.add(.actions, "Ask three people this week")
    #expect(editor.notes.actions.map(\.text) == ["Ask three people this week"])
    hooks.resolve(editor.notes.openThreads[1], true)
    #expect(editor.notes.openThreads.map(\.resolved) == [false, true])
    await editor.settle()

    let stored = try #require(try await store.notes(for: editor.sessionID))
    #expect(stored == editor.notes)
    #expect(stored.decisions.map(\.text) == ["Cap prompts at fifteen minutes"])
    #expect(stored.decisions[0].edited)
    #expect(stored.ideas.isEmpty)
    #expect(stored.actions.map(\.text) == ["Ask three people this week"])
    #expect(stored.actions[0].edited)
    #expect(stored.openThreads.map(\.resolved) == [false, true])
    #expect(try await store.openThreads(limit: 5).map(\.noteItemID) == ["free-tier-purpose"])
    #expect(editor.failure == nil)

    hooks.resolve(editor.notes.openThreads[1], false)
    await editor.settle()
    #expect(try await store.openThreads(limit: 5).count == 2)
    #expect(editor.notes.openThreads.map(\.resolved) == [false, false])
  }

  @Test func anAddedItemKeepsTheStoreIdAfterTheReload() async throws {
    let store = try SessionStore(configuration: .inMemory)
    let editor = try await Self.editor(over: store)

    editor.hooks.add(.questions, "Will people pay seven dollars")
    await editor.settle()
    let added = try #require(editor.notes.questions.first)
    editor.hooks.edit(.questions, added, "Will people pay seven dollars a month")
    await editor.settle()

    let stored = try #require(try await store.notes(for: editor.sessionID))
    #expect(stored.questions.map(\.text) == ["Will people pay seven dollars a month"])
    #expect(stored.questions.map(\.id) == [added.id])
  }

  @Test func aRefusedSavePutsTheNotesBackAndSaysSo() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("notes-editor-\(UUID().uuidString).store")
    let writable = try HistoryModelTests.store(at: url, allowsSave: true)
    let id = try await writable.save(
      result: await HistoryModelTests.result(lines: ["pricing again"]), notes: Self.notes,
      title: "")
    let readOnly = try HistoryModelTests.store(at: url, allowsSave: false)
    let detail = try #require(try await readOnly.detail(id))
    let editor = try #require(NotesEditor(store: readOnly, detail: detail))

    editor.hooks.edit(.decisions, editor.notes.decisions[0], "Cap prompts at an hour")
    #expect(editor.notes.decisions.map(\.text) == ["Cap prompts at an hour"])
    await editor.settle()

    #expect(editor.failure == NotesEditor.saveFailedLine)
    #expect(editor.notes == Self.notes)
    #expect(try await writable.notes(for: id) == Self.notes)
  }

  @Test func aSessionWithoutNotesHasNoEditor() async throws {
    let store = try SessionStore(configuration: .inMemory)
    let id = try await store.save(
      result: await HistoryModelTests.result(lines: ["pricing again"]), notes: nil, title: "")
    let detail = try #require(try await store.detail(id))
    #expect(NotesEditor(store: store, detail: detail) == nil)
  }

  static func editor(over store: SessionStore) async throws -> NotesEditor {
    let id = try await store.save(
      result: await HistoryModelTests.result(lines: ["pricing again"]), notes: notes, title: "")
    let detail = try #require(try await store.detail(id))
    return try #require(NotesEditor(store: store, detail: detail))
  }
}
