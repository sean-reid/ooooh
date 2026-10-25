import Foundation
import State

/// What the client should do after a check.
public enum Decision: Equatable, Sendable {
  case wait
  case prompt(InterventionKind)
  case askIfFinished
  case endSession
  case command(JevAnswers.Command)
}

/// Lightweight signals the client measures itself.
public struct Signals: Equatable, Sendable {
  public var now: TimeInterval
  public var pauseLength: TimeInterval
  public var speechDensity: Double
  public var awaitingFinishedReply: Bool

  public init(
    now: TimeInterval, pauseLength: TimeInterval, speechDensity: Double,
    awaitingFinishedReply: Bool = false
  ) {
    self.now = now
    self.pauseLength = pauseLength
    self.speechDensity = speechDensity
    self.awaitingFinishedReply = awaitingFinishedReply
  }
}

/// Combines Jev's answers with the adaptive floor. Pure, so it runs against fixtures.
public struct Governor: Sendable {
  public var config: GovernorConfig
  public private(set) var lastPromptAt: TimeInterval?
  public private(set) var lastCheckAt: TimeInterval?
  public private(set) var finishedAskedAt: TimeInterval?

  public init(config: GovernorConfig) {
    self.config = config
  }

  /// The current gap required between prompts, from 30 seconds when struggling to 120 when flowing.
  public func floor(for answers: JevAnswers, signals: Signals) -> TimeInterval {
    let struggle = answers.articulationDifficulty.unit
    let flow = answers.momentum.unit
    let density = min(max(signals.speechDensity, 0), 1)
    let ease = (flow + density + (1 - struggle)) / 3
    return config.floor.min + (config.floor.max - config.floor.min) * ease
  }

  public func shouldCheck(signals: Signals, utteranceEnded: Bool) -> Bool {
    if let last = lastCheckAt, signals.now - last < config.minCheckInterval { return false }
    return utteranceEnded || signals.pauseLength >= config.checkPause
  }

  public mutating func decide(_ answers: JevAnswers, signals: Signals) -> Decision {
    lastCheckAt = signals.now

    if answers.addressesApp.choice != .none,
      answers.addressesApp.confidence >= config.command.confidence
    {
      return .command(answers.addressesApp.choice)
    }

    if let asked = finishedAskedAt {
      if signals.now - asked >= config.endSilence, signals.pauseLength >= config.endSilence {
        return .endSession
      }
      if signals.pauseLength < config.checkPause {
        finishedAskedAt = nil
      }
      return .wait
    }

    if answers.seemsFinished.probability >= config.finished.probability {
      finishedAskedAt = signals.now
      return .askIfFinished
    }

    guard answers.goodMoment.probability >= config.speak.probability,
      answers.intervention.confidence >= config.speak.confidence
    else { return .wait }

    if let last = lastPromptAt, signals.now - last < floor(for: answers, signals: signals) {
      return .wait
    }

    lastPromptAt = signals.now
    return .prompt(answers.intervention.choice)
  }
}
