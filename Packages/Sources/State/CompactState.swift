import Foundation

/// The bounded picture of a session that replaces old transcript.
public struct CompactState: Codable, Equatable, Sendable {
  public var currentThread: String
  public var mainIdeas: [Item]
  public var openQuestions: [Item]
  public var uncertainties: [Item]
  public var decisions: [Item]
  public var recentTopics: [String]
  public var lastIntervention: Intervention?
  public var mode: Mode

  public init(
    currentThread: String = "",
    mainIdeas: [Item] = [],
    openQuestions: [Item] = [],
    uncertainties: [Item] = [],
    decisions: [Item] = [],
    recentTopics: [String] = [],
    lastIntervention: Intervention? = nil,
    mode: Mode = .exploring
  ) {
    self.currentThread = currentThread
    self.mainIdeas = mainIdeas
    self.openQuestions = openQuestions
    self.uncertainties = uncertainties
    self.decisions = decisions
    self.recentTopics = recentTopics
    self.lastIntervention = lastIntervention
    self.mode = mode
  }

  public static let empty = CompactState()

  public enum Mode: String, Codable, Sendable {
    case exploring, converging, stuck, finishing
  }

  public struct Item: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var resolved: Bool

    public init(id: String, text: String, resolved: Bool = false) {
      self.id = id
      self.text = text
      self.resolved = resolved
    }
  }

  public struct Intervention: Codable, Equatable, Sendable {
    public var kind: InterventionKind
    public var text: String
    public var at: TimeInterval
    public var takenUp: Bool?

    public init(kind: InterventionKind, text: String, at: TimeInterval, takenUp: Bool? = nil) {
      self.kind = kind
      self.text = text
      self.at = at
      self.takenUp = takenUp
    }
  }
}

public enum InterventionKind: String, Codable, CaseIterable, Sendable {
  case clarify, deepen, reflect, decide, summarize, challenge
}
