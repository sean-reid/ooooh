import Foundation
import Governor

/// Keeps the signals the loop sent with each check, by the check time, around any provider.
public actor SignalRecordingProvider: DecisionProvider {
  let inner: any DecisionProvider
  private var byTime: [Int: Signals] = [:]

  public init(_ inner: any DecisionProvider) {
    self.inner = inner
  }

  public func check(_ input: CheckInput) async throws -> JevAnswers {
    byTime[RecordedDecisionProvider.key(input.signals.now)] = input.signals
    return try await inner.check(input)
  }

  public func signals(at: TimeInterval) -> Signals? {
    byTime[RecordedDecisionProvider.key(at)]
  }
}

/// One check as the policy fit reads it: the loop's signals, every number Jev gave, what the
/// governor decided, and what the scorer would make of a prompt there.
public struct FeatureRow: Equatable, Sendable {
  public static let cueNames = [
    "hangingQuestion", "trailsOff", "unnamedDecision", "contradictsEarlier", "repeatsPoint",
  ]

  static let signalColumns = [
    "fixture", "at", "pauseLength", "speechDensity", "awaitingFinishedReply", "wordsSoFar",
    "promptsSoFar", "secondsSincePrompt", "goodMoment",
  ]
  static let answerColumns = [
    "momentum", "momentumConfidence", "articulation", "articulationConfidence", "seemsFinished",
    "intervention", "interventionConfidence", "decision", "label", "labelKind",
  ]
  public static let columns = signalColumns + cueNames + answerColumns

  public var fixture: String
  public var signals: Signals
  public var answers: JevAnswers
  public var decision: Decision
  public var expectation: Labels.Expectation

  /// One row per check in the result, in order. A check whose signals were not captured is skipped.
  public static func rows(
    fixture: String, result: SessionResult, labels: Labels, signals: (TimeInterval) -> Signals?
  ) -> [FeatureRow] {
    let ends = UtteranceEnds(result.transcript)
    return result.records.compactMap { record in
      guard case .check(let at, _, let answers, let decision) = record,
        let signals = signals(at)
      else { return nil }
      return FeatureRow(
        fixture: fixture, signals: signals, answers: answers, decision: decision,
        expectation: labels.expectation(at: at, ends: ends))
    }
  }

  public static var csvHeader: String { columns.joined(separator: ",") }

  /// Numbers print as Swift does, empty where a value is absent: a cue Jev did not answer,
  /// or seconds since a prompt before the first one.
  public var csvLine: String {
    func text(_ value: Double?) -> String { value.map { "\($0)" } ?? "" }
    var fields: [String] = [
      fixture, text(signals.now), text(signals.pauseLength), text(signals.speechDensity),
      signals.awaitingFinishedReply ? "1" : "0", "\(signals.wordsSoFar)",
      "\(signals.promptsSoFar)", text(signals.secondsSincePrompt),
      text(answers.goodMoment.probability),
    ]
    fields += Self.cueNames.map { text(answers.cues[$0]) }
    fields += [
      text(answers.momentum.score), text(answers.momentum.confidence),
      text(answers.articulationDifficulty.score), text(answers.articulationDifficulty.confidence),
      text(answers.seemsFinished.probability), answers.intervention.choice.rawValue,
      text(answers.intervention.confidence), decision.featureName, expectation.name,
      expectation.kind ?? "",
    ]
    return fields.joined(separator: ",")
  }

  public static func csv(_ rows: [FeatureRow]) -> String {
    ([csvHeader] + rows.map(\.csvLine)).joined(separator: "\n") + "\n"
  }
}

extension Decision {
  /// `wait`, `prompt:clarify`, `askIfFinished`, `endSession`, `command:recall`.
  public var featureName: String {
    switch self {
    case .wait: "wait"
    case .prompt(let kind): "prompt:\(kind.rawValue)"
    case .askIfFinished: "askIfFinished"
    case .endSession: "endSession"
    case .command(let command): "command:\(command.rawValue)"
    }
  }
}
