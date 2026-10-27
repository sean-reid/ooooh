import Foundation
import Notes
import State
import Transcription

/// One row of the history list.
public struct SessionSummary: Sendable, Equatable, Identifiable {
  public var id: UUID
  public var title: String
  public var summary: String?
  public var startedAt: Date
  public var duration: TimeInterval
  public var openThreadCount: Int

  public init(
    id: UUID, title: String, summary: String? = nil, startedAt: Date, duration: TimeInterval,
    openThreadCount: Int
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.startedAt = startedAt
    self.duration = duration
    self.openThreadCount = openThreadCount
  }
}

/// Everything the session screen shows for a past session.
public struct SessionDetail: Sendable, Equatable {
  public var summary: SessionSummary
  public var endedAt: Date
  public var modeAtEnd: CompactState.Mode?
  public var state: CompactState?
  public var transcript: [Segment]
  public var lines: [SpokenLine]
  public var notes: SessionNotes?
  public var items: [NoteEntry]
  public var audioPath: String?
  public var keepAudio: Bool
}

/// A stored note item with the handle the edit calls take.
public struct NoteEntry: Sendable, Equatable, Identifiable {
  public var id: UUID
  public var section: NoteSection
  public var item: NoteItem
}

/// An unresolved thread from a past session, offered at the start of the next one.
public struct OpenThread: Sendable, Equatable, Identifiable {
  public var id: UUID
  public var text: String
  public var sessionID: UUID
  public var sessionTitle: String
  public var sessionStartedAt: Date
  public var noteItemID: String
}

public struct MarkdownDocument: Sendable, Equatable {
  public var filename: String
  public var contents: String
}

public enum StoreError: Error, Equatable {
  case missingSession(UUID)
  case missingItem(UUID)
  case missingLine(UUID)
  case missingThread(UUID)
}
