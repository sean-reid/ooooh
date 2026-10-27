import Foundation
import Notes
import NotesUI
import Observation
import Persistence
import Transcription

/// The notes of one saved session as the screen edits them. Each change shows at once, is
/// written to the store in order, and the notes are read back, so what stays is what is saved.
@MainActor @Observable
final class NotesEditor {
  static let saveFailedLine = "That change couldn't be saved. The notes are as they were."

  let store: SessionStore
  let sessionID: UUID
  let transcript: [Segment]
  let date: Date
  private(set) var notes: SessionNotes
  private(set) var failure: String?
  private var entries: [NoteEntry]
  private var pending: Task<Void, Never>?

  /// Nil when the session has no notes.
  init?(store: SessionStore, detail: SessionDetail) {
    guard let notes = detail.notes else { return nil }
    self.store = store
    self.sessionID = detail.summary.id
    self.transcript = detail.transcript
    self.date = detail.summary.startedAt
    self.notes = notes
    self.entries = detail.items
  }

  var hooks: NoteEditing {
    NoteEditing(
      edit: { [weak self] section, item, text in self?.edit(item, in: section, text: text) },
      delete: { [weak self] section, item in self?.delete(item, in: section) },
      add: { [weak self] section, text in self?.add(text, to: section) },
      resolve: { [weak self] item, resolved in self?.setResolved(item, resolved) })
  }

  /// Waits for every change made so far to reach the store.
  func settle() async {
    await pending?.value
  }

  func edit(_ item: NoteItem, in section: NoteSection, text: String) {
    guard let index = notes[section].firstIndex(where: { $0.id == item.id }) else { return }
    let before = notes
    notes[section][index].text = text
    notes[section][index].edited = true
    enqueue(restoring: before) { editor in
      try await editor.store.editItem(try editor.entry(item, in: section), text: text)
    }
  }

  func delete(_ item: NoteItem, in section: NoteSection) {
    let before = notes
    notes[section].removeAll { $0.id == item.id }
    enqueue(restoring: before) { editor in
      try await editor.store.deleteItem(try editor.entry(item, in: section))
    }
  }

  func add(_ text: String, to section: NoteSection) {
    let before = notes
    notes[section].append(NoteItem(id: UUID().uuidString.lowercased(), text: text, edited: true))
    enqueue(restoring: before) { editor in
      try await editor.store.addItem(text, section: section, to: editor.sessionID)
    }
  }

  func setResolved(_ item: NoteItem, _ resolved: Bool) {
    let before = notes
    if let index = notes.openThreads.firstIndex(where: { $0.id == item.id }) {
      notes.openThreads[index].resolved = resolved
    }
    enqueue(restoring: before) { editor in
      try await editor.store.editItem(try editor.entry(item, in: .openThreads), resolved: resolved)
    }
  }

  /// The screen changes at once; the write runs after the ones before it, and the notes are
  /// read back. A refused write puts back `before`, under a line saying so.
  private func enqueue(
    restoring before: SessionNotes,
    _ write: @escaping @MainActor (NotesEditor) async throws -> Void
  ) {
    let previous = pending
    pending = Task {
      await previous?.value
      failure = nil
      do {
        try await write(self)
        await reload()
      } catch {
        notes = before
        failure = Self.saveFailedLine
      }
    }
  }

  private func reload() async {
    guard let detail = try? await store.detail(sessionID), let stored = detail.notes else { return }
    notes = stored
    entries = detail.items
  }

  private func entry(_ item: NoteItem, in section: NoteSection) throws -> UUID {
    guard let entry = entries.first(where: { $0.section == section && $0.item.id == item.id })
    else { throw MissingEntry() }
    return entry.id
  }

  private struct MissingEntry: Error {}
}
