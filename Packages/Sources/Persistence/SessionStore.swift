import Foundation
import Notes
import Session
import State
import SwiftData
import Transcription

/// The only way in and out of the store. Model objects never leave the actor.
@ModelActor
public actor SessionStore {
  public init(configuration: StoreConfiguration) throws {
    self.init(modelContainer: try PersistenceContainer.make(configuration))
  }

  /// Saves a finished session and returns its id. Notes can come later through `attachNotes`.
  /// The duration runs from `startedAt` to `endedAt`; without an end it runs to the last record.
  @discardableResult
  public func save(
    result: SessionResult, notes: SessionNotes?, title: String, startedAt: Date = .now,
    endedAt: Date? = nil, audioPath: String? = nil, keepAudio: Bool = false
  ) throws -> UUID {
    let duration =
      endedAt.map { max(0, $0.timeIntervalSince(startedAt)) } ?? Self.duration(of: result)
    let session = StoredSession(
      startedAt: startedAt, endedAt: startedAt.addingTimeInterval(duration), duration: duration,
      title: title, modeAtEnd: result.state.mode.rawValue,
      state: try JSONEncoder().encode(result.state), audioPath: keepAudio ? audioPath : nil,
      keepAudio: keepAudio)
    modelContext.insert(session)
    for (order, segment) in result.transcript.enumerated() where segment.isFinal {
      let stored = StoredSegment(
        text: segment.text, start: segment.start, end: segment.end, order: order)
      stored.session = session
      modelContext.insert(stored)
    }
    if let notes {
      try attach(notes, to: session)
    }
    try modelContext.save()
    return session.id
  }

  /// Replaces the generated items and the summary with new ones. Items the user edited
  /// stay, and a thread keeps its resolved state when the new notes still carry it.
  public func attachNotes(_ notes: SessionNotes, to sessionID: UUID) throws {
    let session = try session(sessionID)
    try attach(notes, to: session)
    try modelContext.save()
  }

  public func delete(session sessionID: UUID) throws {
    let session = try session(sessionID)
    removeAudio(at: session.audioPath)
    modelContext.delete(session)
    try modelContext.save()
  }

  public func deleteEverything() throws {
    for session in try modelContext.fetch(FetchDescriptor<StoredSession>()) {
      removeAudio(at: session.audioPath)
    }
    try modelContext.delete(model: StoredThread.self)
    try modelContext.delete(model: StoredNoteItem.self)
    try modelContext.delete(model: StoredSegment.self)
    try modelContext.delete(model: StoredSession.self)
    try modelContext.save()
  }

  func session(_ id: UUID) throws -> StoredSession {
    var descriptor = FetchDescriptor<StoredSession>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    guard let session = try modelContext.fetch(descriptor).first else {
      throw StoreError.missingSession(id)
    }
    return session
  }

  func attach(_ notes: SessionNotes, to session: StoredSession) throws {
    let existing = session.items ?? []
    let kept = existing.filter(\.edited)
    for item in existing where !item.edited {
      modelContext.delete(item)
    }
    var order = 0
    for section in NoteSection.allCases {
      for item in notes[section] {
        order += 1
        if let keep = kept.first(where: { $0.section == section.rawValue && $0.slug == item.id }) {
          keep.order = order
          continue
        }
        let stored = StoredNoteItem(
          section: section.rawValue, slug: item.id, text: item.text, spanStart: item.span?.start,
          spanEnd: item.span?.end, edited: item.edited, resolved: item.resolved, order: order)
        stored.session = session
        modelContext.insert(stored)
      }
    }
    let threads = session.openedThreads ?? []
    let keptSlugs = Set(kept.filter { $0.section == NoteSection.openThreads.rawValue }.map(\.slug))
    let newSlugs = Set(notes.openThreads.map(\.id))
    for thread in threads where !newSlugs.contains(thread.sourceNoteItemSlug) {
      if !keptSlugs.contains(thread.sourceNoteItemSlug) {
        modelContext.delete(thread)
      }
    }
    for (order, item) in notes.openThreads.enumerated() {
      if let thread = threads.first(where: { $0.sourceNoteItemSlug == item.id }) {
        thread.order = order
        if !keptSlugs.contains(item.id) {
          thread.text = item.text
        }
      } else {
        let thread = StoredThread(text: item.text, sourceNoteItemSlug: item.id)
        thread.order = order
        thread.resolved = item.resolved
        thread.sourceSession = session
        modelContext.insert(thread)
      }
    }
    if !notes.title.isEmpty {
      session.title = notes.title
    }
    session.summary = notes.summary
    try refreshOpenThreadCount(session)
  }

  func refreshOpenThreadCount(_ session: StoredSession) throws {
    let id = session.id
    session.openThreadCount = try modelContext.fetchCount(
      FetchDescriptor<StoredThread>(
        predicate: #Predicate { $0.sourceSession?.id == id && !$0.resolved }))
  }

  func removeAudio(at path: String?) {
    guard let path else { return }
    try? FileManager.default.removeItem(atPath: path)
  }

  static func duration(of result: SessionResult) -> TimeInterval {
    for record in result.records.reversed() {
      if case .ended(let at, _) = record { return at }
    }
    return result.transcript.last?.end ?? 0
  }
}
