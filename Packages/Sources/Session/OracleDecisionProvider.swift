import Foundation
import Governor
import State

/// Answers straight from the labels, once per label at the utterance end.
/// Scores perfectly if the loop and the scorer agree, so it checks the harness, not the model.
public struct OracleDecisionProvider: DecisionProvider {
  let byEnd: [TimeInterval: Labels.Label]

  public init(labels: Labels) {
    byEnd = Dictionary(labels.labels.map { ($0.at, $0) }, uniquingKeysWith: { a, _ in a })
  }

  public func check(_ input: CheckInput) async throws -> JevAnswers {
    var answers = JevAnswers.quiet
    guard input.signals.pauseLength == 0, let last = input.recentTranscript.last,
      let label = byEnd[last.end]
    else { return answers }
    if label.kind == Labels.finishedKind {
      answers.seemsFinished = .init(0.99)
    } else if let command = JevAnswers.Command(rawValue: label.kind), command != .none {
      answers.addressesApp = .init(command, confidence: 0.99)
    } else if let kind = InterventionKind(rawValue: label.kind) {
      answers.goodMoment = .init(0.99)
      answers.intervention = .init(kind, confidence: 0.99)
      answers.articulationDifficulty = .init(5, confidence: 0.9)
      answers.momentum = .init(1, confidence: 0.9)
    }
    return answers
  }
}

/// Replays answers a real provider gave, keyed by the time of the check to the
/// millisecond, so a changed check schedule still gets the answer Jev gave at that moment.
public struct RecordedDecisionProvider: DecisionProvider {
  public struct Entry: Codable, Sendable {
    public var checkIndex: Int
    public var at: TimeInterval
    public var answers: JevAnswers

    public init(checkIndex: Int, at: TimeInterval, answers: JevAnswers) {
      self.checkIndex = checkIndex
      self.at = at
      self.answers = answers
    }
  }

  let answers: [Int: JevAnswers]

  public init(entries: [Entry]) {
    answers = Dictionary(
      entries.map { (Self.key($0.at), $0.answers) }, uniquingKeysWith: { a, _ in a })
  }

  /// One JSON object per line.
  public init(contentsOf url: URL) throws {
    let text = try String(contentsOf: url, encoding: .utf8)
    let decoder = JSONDecoder()
    let entries = try text.split(separator: "\n").map {
      try decoder.decode(Entry.self, from: Data($0.utf8))
    }
    self.init(entries: entries)
  }

  public func check(_ input: CheckInput) async throws -> JevAnswers {
    answers[Self.key(input.signals.now)] ?? .quiet
  }

  /// Whether a check at this moment has a recorded answer; without one it replays `.quiet`.
  public func hasAnswer(at: TimeInterval) -> Bool {
    answers[Self.key(at)] != nil
  }

  static func key(_ at: TimeInterval) -> Int { Int((at * 1000).rounded()) }
}
