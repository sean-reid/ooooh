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

  /// The sections with an item in them, in reading order.
  public var sections: [(section: NoteSection, items: [NoteItem])] {
    NoteSection.allCases.map { ($0, self[$0]) }.filter { !$0.items.isEmpty }
  }

  public subscript(section: NoteSection) -> [NoteItem] {
    get {
      switch section {
      case .ideas: ideas
      case .decisions: decisions
      case .questions: questions
      case .insights: insights
      case .actions: actions
      case .openThreads: openThreads
      case .quotes: quotes
      }
    }
    set {
      switch section {
      case .ideas: ideas = newValue
      case .decisions: decisions = newValue
      case .questions: questions = newValue
      case .insights: insights = newValue
      case .actions: actions = newValue
      case .openThreads: openThreads = newValue
      case .quotes: quotes = newValue
      }
    }
  }
}

public enum NoteSection: String, CaseIterable, Sendable, Codable {
  case ideas, decisions, questions, insights, actions, openThreads, quotes

  public var title: String {
    switch self {
    case .ideas: "Ideas"
    case .decisions: "Decisions"
    case .questions: "Questions"
    case .insights: "Insights"
    case .actions: "Actions"
    case .openThreads: "Open threads"
    case .quotes: "Quotes"
    }
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
