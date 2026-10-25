import Foundation
import Notes
import State
import SwiftData
import Transcription

extension SessionStore {
  /// Newest first.
  public func sessions(limit: Int = 50, offset: Int = 0) throws -> [SessionSummary] {
    var descriptor = FetchDescriptor<StoredSession>(
      sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
    descriptor.fetchLimit = limit
    descriptor.fetchOffset = offset
    return try modelContext.fetch(descriptor).map(Self.summary)
  }

  /// Sessions with the query in a segment, a note item, or the summary, newest first. Case
  /// and diacritics do not matter.
  public func search(_ query: String) throws -> [SessionSummary] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return [] }
    let inText = FetchDescriptor<StoredSession>(
      predicate: #Predicate { session in
        (session.segments?.contains { $0.text.localizedStandardContains(needle) } ?? false)
          || (session.items?.contains { $0.text.localizedStandardContains(needle) } ?? false)
      })
    let inSummary = FetchDescriptor<StoredSession>(
      predicate: #Predicate { $0.summary?.localizedStandardContains(needle) ?? false })
    var seen = Set<UUID>()
    return try (modelContext.fetch(inText) + modelContext.fetch(inSummary))
      .filter { seen.insert($0.id).inserted }
      .sorted { $0.startedAt > $1.startedAt }
      .map(Self.summary)
  }

  /// Unresolved threads, most recent session first, in note order within a session.
  public func openThreads(limit: Int = 3) throws -> [OpenThread] {
    guard limit > 0 else { return [] }
    let descriptor = FetchDescriptor<StoredThread>(predicate: #Predicate { !$0.resolved })
    let threads = try modelContext.fetch(descriptor)
      .compactMap { thread -> (OpenThread, Int)? in
        guard let session = thread.sourceSession else { return nil }
        let open = OpenThread(
          id: thread.id, text: thread.text, sessionID: session.id, sessionTitle: session.title,
          sessionStartedAt: session.startedAt, noteItemID: thread.sourceNoteItemSlug)
        return (open, thread.order)
      }
      .sorted { a, b in
        a.0.sessionStartedAt != b.0.sessionStartedAt
          ? a.0.sessionStartedAt > b.0.sessionStartedAt : a.1 < b.1
      }
    return Array(threads.map(\.0).prefix(limit))
  }

  public func detail(_ sessionID: UUID) throws -> SessionDetail? {
    guard let session = try? session(sessionID) else { return nil }
    let items = Self.entries(of: session)
    let state = try session.state.map { try JSONDecoder().decode(CompactState.self, from: $0) }
    return SessionDetail(
      summary: Self.summary(session), endedAt: session.endedAt,
      modeAtEnd: CompactState.Mode(rawValue: session.modeAtEnd), state: state,
      transcript: Self.transcript(of: session), notes: Self.notes(of: session, items: items),
      items: items, audioPath: session.audioPath, keepAudio: session.keepAudio)
  }

  public func notes(for sessionID: UUID) throws -> SessionNotes? {
    let session = try session(sessionID)
    return Self.notes(of: session, items: Self.entries(of: session))
  }

  public func items(in sessionID: UUID) throws -> [NoteEntry] {
    Self.entries(of: try session(sessionID))
  }

  static func summary(_ session: StoredSession) -> SessionSummary {
    SessionSummary(
      id: session.id, title: session.title, summary: session.summary,
      startedAt: session.startedAt, duration: session.duration,
      openThreadCount: session.openThreadCount)
  }

  static func transcript(of session: StoredSession) -> [Segment] {
    (session.segments ?? []).sorted { $0.order < $1.order }.map {
      Segment(text: $0.text, start: $0.start, end: $0.end, isFinal: true)
    }
  }

  static func entries(of session: StoredSession) -> [NoteEntry] {
    (session.items ?? []).sorted { $0.order < $1.order }.compactMap { stored in
      guard let section = NoteSection(rawValue: stored.section) else { return nil }
      var span: TranscriptSpan?
      if let start = stored.spanStart, let end = stored.spanEnd {
        span = TranscriptSpan(start: start, end: end)
      }
      let item = NoteItem(
        id: stored.slug, text: stored.text, span: span, edited: stored.edited,
        resolved: stored.resolved)
      return NoteEntry(id: stored.id, section: section, item: item)
    }
  }

  static func notes(of session: StoredSession, items: [NoteEntry]) -> SessionNotes? {
    guard !items.isEmpty || session.summary != nil else { return nil }
    var notes = SessionNotes(title: session.title, summary: session.summary)
    for entry in items {
      switch entry.section {
      case .ideas: notes.ideas.append(entry.item)
      case .decisions: notes.decisions.append(entry.item)
      case .questions: notes.questions.append(entry.item)
      case .insights: notes.insights.append(entry.item)
      case .actions: notes.actions.append(entry.item)
      case .openThreads: notes.openThreads.append(entry.item)
      case .quotes: notes.quotes.append(entry.item)
      }
    }
    return notes
  }
}
