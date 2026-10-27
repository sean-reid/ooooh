import Foundation
import State
import Transcription

/// The structured output of a session. Every item points back at the transcript.
public struct SessionNotes: Codable, Equatable, Sendable {
  public var title: String
  public var summary: String?
  public var ideas: [NoteItem]
  public var decisions: [NoteItem]
  public var questions: [NoteItem]
  public var insights: [NoteItem]
  public var actions: [NoteItem]
  public var openThreads: [NoteItem]
  public var quotes: [NoteItem]

  public init(
    title: String,
    summary: String? = nil,
    ideas: [NoteItem] = [],
    decisions: [NoteItem] = [],
    questions: [NoteItem] = [],
    insights: [NoteItem] = [],
    actions: [NoteItem] = [],
    openThreads: [NoteItem] = [],
    quotes: [NoteItem] = []
  ) {
    self.title = title
    self.summary = summary
    self.ideas = ideas
    self.decisions = decisions
    self.questions = questions
    self.insights = insights
    self.actions = actions
    self.openThreads = openThreads
    self.quotes = quotes
  }

  public var sections: [(name: String, items: [NoteItem])] {
    [
      ("Ideas", ideas), ("Decisions", decisions), ("Questions", questions),
      ("Insights", insights), ("Actions", actions), ("Open threads", openThreads),
      ("Quotes", quotes),
    ].filter { !$0.1.isEmpty }
  }
}

public struct NoteItem: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var text: String
  public var span: TranscriptSpan?
  public var edited: Bool
  public var resolved: Bool

  public init(
    id: String, text: String, span: TranscriptSpan? = nil, edited: Bool = false,
    resolved: Bool = false
  ) {
    self.id = id
    self.text = text
    self.span = span
    self.edited = edited
    self.resolved = resolved
  }

  /// The Worker sends `id`, `text`, and `span`; the editing flags are the app's.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    text = try container.decode(String.self, forKey: .text)
    span = try container.decodeIfPresent(TranscriptSpan.self, forKey: .span)
    edited = try container.decodeIfPresent(Bool.self, forKey: .edited) ?? false
    resolved = try container.decodeIfPresent(Bool.self, forKey: .resolved) ?? false
  }
}

public struct TranscriptSpan: Codable, Equatable, Sendable {
  public var start: TimeInterval
  public var end: TimeInterval

  public init(start: TimeInterval, end: TimeInterval) {
    self.start = start
    self.end = end
  }
}

extension TranscriptSpan {
  /// The words of every segment that overlaps the span, in order.
  public func text(in transcript: [Segment]) -> String {
    transcript
      .filter { $0.end >= start && $0.start <= end }
      .map(\.text)
      .joined(separator: " ")
  }
}
