import Foundation
import Governor
import State

/// Answers straight from the labels. Scores perfectly if the loop and the
/// scorer agree, so it checks the harness, not the model.
public struct OracleDecisionProvider: DecisionProvider {
  let byEnd: [TimeInterval: Labels.Label]

  public init(labels: Labels) {
    byEnd = Dictionary(labels.labels.map { ($0.at, $0) }, uniquingKeysWith: { a, _ in a })
  }

  public func check(_ input: CheckInput) async throws -> JevAnswers {
    var answers = JevAnswers.quiet
    guard let last = input.recentTranscript.last, let label = byEnd[last.end],
      input.signals.pauseLength < input.signals.now - last.end + 0.001
    else { return answers }
    if label.kind == Labels.finishedKind {
      answers.seemsFinished = .init(0.99)
    } else if let kind = InterventionKind(rawValue: label.kind) {
      answers.goodMoment = .init(0.99)
      answers.intervention = .init(kind, confidence: 0.99)
      answers.articulationDifficulty = .init(5, confidence: 0.9)
      answers.momentum = .init(1, confidence: 0.9)
    }
    return answers
  }
}

/// Replays answers a real provider gave, keyed by check index.
public struct RecordedDecisionProvider: DecisionProvider {
  public struct Entry: Codable, Sendable {
    public var checkIndex: Int
    public var answers: JevAnswers

    public init(checkIndex: Int, answers: JevAnswers) {
      self.checkIndex = checkIndex
      self.answers = answers
    }
  }

  let answers: [Int: JevAnswers]

  public init(entries: [Entry]) {
    answers = Dictionary(
      entries.map { ($0.checkIndex, $0.answers) }, uniquingKeysWith: { a, _ in a })
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
    answers[input.checkIndex] ?? .quiet
  }
}
