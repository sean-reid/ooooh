import Foundation
import State

/// One check's answers from Jev, evaluated in parallel on the same input.
public struct JevAnswers: Codable, Equatable, Sendable {
  public var articulationDifficulty: Score
  public var momentum: Score
  public var seemsFinished: Noul
  public var addressesApp: Choice<Command>
  /// Atomic yes/no cues about the last few utterances, by name, one per intervention kind.
  public var cues: [String: Double]

  public init(
    articulationDifficulty: Score,
    momentum: Score,
    seemsFinished: Noul,
    addressesApp: Choice<Command>,
    cues: [String: Double] = [:]
  ) {
    self.articulationDifficulty = articulationDifficulty
    self.momentum = momentum
    self.seemsFinished = seemsFinished
    self.addressesApp = addressesApp
    self.cues = cues
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    articulationDifficulty = try c.decode(Score.self, forKey: .articulationDifficulty)
    momentum = try c.decode(Score.self, forKey: .momentum)
    seemsFinished = try c.decode(Noul.self, forKey: .seemsFinished)
    addressesApp = try c.decode(Choice<Command>.self, forKey: .addressesApp)
    cues = try c.decodeIfPresent([String: Double].self, forKey: .cues) ?? [:]
  }

  /// A yes/no probability.
  public struct Noul: Codable, Equatable, Sendable {
    public var probability: Double
    public init(_ probability: Double) { self.probability = probability }
  }

  /// A pick from declared options with a confidence.
  public struct Choice<Option: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var choice: Option
    public var confidence: Double
    public init(_ choice: Option, confidence: Double) {
      self.choice = choice
      self.confidence = confidence
    }
  }

  /// A rubric score from 1 to 5 with a confidence. Fractional, since Jev averages over the levels.
  public struct Score: Codable, Equatable, Sendable {
    public var score: Double
    public var confidence: Double
    public init(_ score: Double, confidence: Double) {
      self.score = score
      self.confidence = confidence
    }

    /// 0 for the lowest rubric step, 1 for the highest.
    public var unit: Double { min(max((score - 1) / 4, 0), 1) }
  }

  public enum Command: String, Codable, Sendable {
    case none, recall, wrapUp
  }
}
