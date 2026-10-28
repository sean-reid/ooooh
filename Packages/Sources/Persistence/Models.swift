import Foundation
import SwiftData

// CloudKit sync needs every attribute optional or defaulted, every
// relationship optional with an inverse, and no unique constraints.

@Model
public final class StoredSession {
  public var id: UUID = UUID()
  public var startedAt: Date = Date()
  public var endedAt: Date = Date()
  public var duration: TimeInterval = 0
  public var title: String = ""
  public var summary: String? = nil
  public var modeAtEnd: String = "exploring"
  public var state: Data? = nil
  public var audioPath: String? = nil
  public var keepAudio: Bool = false
  public var openThreadCount: Int = 0

  @Relationship(deleteRule: .cascade, inverse: \StoredSegment.session)
  public var segments: [StoredSegment]? = []

  @Relationship(deleteRule: .cascade, inverse: \StoredLine.session)
  public var lines: [StoredLine]? = []

  @Relationship(deleteRule: .cascade, inverse: \StoredNoteItem.session)
  public var items: [StoredNoteItem]? = []

  @Relationship(deleteRule: .cascade, inverse: \StoredThread.sourceSession)
  public var openedThreads: [StoredThread]? = []

  @Relationship(deleteRule: .nullify, inverse: \StoredThread.resolvedIn)
  public var resolvedThreads: [StoredThread]? = []

  public init(
    id: UUID = UUID(), startedAt: Date, endedAt: Date, duration: TimeInterval, title: String,
    modeAtEnd: String, state: Data?, audioPath: String?, keepAudio: Bool
  ) {
    self.id = id
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.duration = duration
    self.title = title
    self.modeAtEnd = modeAtEnd
    self.state = state
    self.audioPath = audioPath
    self.keepAudio = keepAudio
  }
}

@Model
public final class StoredSegment {
  public var text: String = ""
  public var start: TimeInterval = 0
  public var end: TimeInterval = 0
  public var order: Int = 0
  public var session: StoredSession? = nil

  public init(text: String, start: TimeInterval, end: TimeInterval, order: Int) {
    self.text = text
    self.start = start
    self.end = end
    self.order = order
  }
}

@Model
public final class StoredLine {
  public var id: UUID = UUID()
  public var text: String = ""
  public var kind: String = ""
  public var at: TimeInterval = 0
  public var spoken: Bool = false
  public var cut: Bool = false
  public var bad: Bool = false
  public var order: Int = 0
  public var session: StoredSession? = nil

  public init(
    id: UUID = UUID(), text: String, kind: String, at: TimeInterval, spoken: Bool, cut: Bool,
    bad: Bool, order: Int
  ) {
    self.id = id
    self.text = text
    self.kind = kind
    self.at = at
    self.spoken = spoken
    self.cut = cut
    self.bad = bad
    self.order = order
  }
}

@Model
public final class StoredNoteItem {
  public var id: UUID = UUID()
  public var section: String = "ideas"
  public var slug: String = ""
  public var text: String = ""
  public var spanStart: TimeInterval? = nil
  public var spanEnd: TimeInterval? = nil
  public var edited: Bool = false
  public var resolved: Bool = false
  public var order: Int = 0
  public var session: StoredSession? = nil

  public init(
    id: UUID = UUID(), section: String, slug: String, text: String, spanStart: TimeInterval?,
    spanEnd: TimeInterval?, edited: Bool, resolved: Bool, order: Int
  ) {
    self.id = id
    self.section = section
    self.slug = slug
    self.text = text
    self.spanStart = spanStart
    self.spanEnd = spanEnd
    self.edited = edited
    self.resolved = resolved
    self.order = order
  }
}

@Model
public final class StoredThread {
  public var id: UUID = UUID()
  public var text: String = ""
  public var sourceNoteItemSlug: String = ""
  public var order: Int = 0
  public var resolved: Bool = false
  public var resolvedAt: Date? = nil
  public var sessionStartedAt: Date = Date.distantPast
  public var sourceSession: StoredSession? = nil
  public var resolvedIn: StoredSession? = nil

  public init(id: UUID = UUID(), text: String, sourceNoteItemSlug: String) {
    self.id = id
    self.text = text
    self.sourceNoteItemSlug = sourceNoteItemSlug
  }
}
