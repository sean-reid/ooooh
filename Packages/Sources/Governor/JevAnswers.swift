import Foundation
import State

/// One check's answers from Jev. Six questions, evaluated in parallel on the same input.
public struct JevAnswers: Codable, Equatable, Sendable {
  public var goodMoment: Noul
  public var intervention: Choice<InterventionKind>
  public var articulationDifficulty: Score
  public var momentum: Score
  public var seemsFinished: Noul
  public var addressesApp: Choice<Command>

  public init(
    goodMoment: Noul,
    intervention: Choice<InterventionKind>,
    articulationDifficulty: Score,
    momentum: Score,
    seemsFinished: Noul,
    addressesApp: Choice<Command>
  ) {
    self.goodMoment = goodMoment
    self.intervention = intervention
    self.articulationDifficulty = articulationDifficulty
    self.momentum = momentum
    self.seemsFinished = seemsFinished
    self.addressesApp = addressesApp
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

  /// A rubric score from 1 to 5 with a confidence.
  public struct Score: Codable, Equatable, Sendable {
    public var score: Int
    public var confidence: Double
    public init(_ score: Int, confidence: Double) {
      self.score = score
      self.confidence = confidence
    }

    /// 0 for the lowest rubric step, 1 for the highest.
    public var unit: Double { Double(score - 1) / 4 }
  }

  public enum Command: String, Codable, Sendable {
    case none, recall, wrapUp
  }
}
