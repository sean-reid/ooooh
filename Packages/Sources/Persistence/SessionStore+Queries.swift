import Foundation
import Notes
import State
import SwiftData
import Transcription

extension SessionStore {
  /// Newest first.
  public func sessions(limit: Int = 50, offset: Int = 0) throws -> [SessionSummary] {
    var descriptor = Self.summaryDescriptor()
    descriptor.fetchLimit = limit
    descriptor.fetchOffset = offset
    return try modelContext.fetch(descriptor).map(Self.summary)
  }

  public func sessionCount() throws -> Int {
    try modelContext.fetchCount(FetchDescriptor<StoredSession>())
  }

  /// The newest `limit` sessions with the query in a segment, a note item, or the summary.
  /// Case and diacritics do not matter. Returns nothing once the calling task is cancelled.
  public func search(_ query: String, limit: Int = 50) throws -> [SessionSummary] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty, limit > 0 else { return [] }
    try Task.checkCancellation()
    let inText = #Predicate<StoredSession> { session in
      (session.segments?.contains { $0.text.localizedStandardContains(needle) } ?? false)
        || (session.items?.contains { $0.text.localizedStandardContains(needle) } ?? false)
    }
    let inSummary = #Predicate<StoredSession> {
      $0.summary?.localizedStandardContains(needle) ?? false
    }
    var descriptor = Self.summaryDescriptor(
      predicate: #Predicate { inSummary.evaluate($0) || inText.evaluate($0) })
    descriptor.fetchLimit = limit
    return try modelContext.fetch(descriptor).map(Self.summary)
  }

  /// Unresolved threads, most recent session first, in note order within a session.
  public func openThreads(limit: Int = 3) throws -> [OpenThread] {
    guard limit > 0 else { return [] }
    // The sort key lives on the thread; a key path through the optional session crashes a Release build.
    var descriptor = FetchDescriptor<StoredThread>(
      predicate: #Predicate { !$0.resolved && $0.sourceSession != nil },
      sortBy: [SortDescriptor(\.sessionStartedAt, order: .reverse), SortDescriptor(\.order)])
    descriptor.fetchLimit = limit
    return try modelContext.fetch(descriptor).compactMap { thread in
      guard let session = thread.sourceSession else { return nil }
      return OpenThread(
        id: thread.id, text: thread.text, sessionID: session.id, sessionTitle: session.title,
        sessionStartedAt: session.startedAt, noteItemID: thread.sourceNoteItemSlug)
    }
  }

  public func detail(_ sessionID: UUID) throws -> SessionDetail? {
    guard let session = try? session(sessionID) else { return nil }
    let items = Self.entries(of: session)
    let state = try session.state.map { try JSONDecoder().decode(CompactState.self, from: $0) }
    return SessionDetail(
      summary: Self.summary(session), endedAt: session.endedAt,
      modeAtEnd: CompactState.Mode(rawValue: session.modeAtEnd), state: state,
      transcript: Self.transcript(of: session), lines: Self.lines(of: session),
      notes: Self.notes(of: session, items: items),
      items: items, audioPath: session.audioPath, keepAudio: session.keepAudio)
  }

  public func notes(for sessionID: UUID) throws -> SessionNotes? {
    let session = try session(sessionID)
    return Self.notes(of: session, items: Self.entries(of: session))
  }

  public func items(in sessionID: UUID) throws -> [NoteEntry] {
    Self.entries(of: try session(sessionID))
  }

  /// Newest first.
  static func summaryDescriptor(predicate: Predicate<StoredSession>? = nil)
    -> FetchDescriptor<StoredSession>
  {
    FetchDescriptor<StoredSession>(
      predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
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

  static func lines(of session: StoredSession) -> [SpokenLine] {
    (session.lines ?? []).sorted { $0.order < $1.order }.compactMap { stored in
      guard let kind = SpokenLine.Kind(name: stored.kind) else { return nil }
      return SpokenLine(
        id: stored.id, text: stored.text, kind: kind, at: stored.at, spoken: stored.spoken,
        cut: stored.cut, bad: stored.bad)
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
      notes[entry.section].append(entry.item)
    }
    return notes
  }
}
