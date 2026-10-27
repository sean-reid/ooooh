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

/// Lightweight signals the client measures itself. `now` is seconds since the session started.
public struct Signals: Equatable, Sendable {
  public var now: TimeInterval
  public var pauseLength: TimeInterval
  public var speechDensity: Double
  public var awaitingFinishedReply: Bool
  /// Words in every final utterance so far.
  public var wordsSoFar: Int
  /// Interventions spoken so far this session; the finished question is not one.
  public var promptsSoFar: Int
  /// Seconds since the last intervention spoke, nil before the first.
  public var secondsSincePrompt: TimeInterval?

  public init(
    now: TimeInterval, pauseLength: TimeInterval, speechDensity: Double,
    awaitingFinishedReply: Bool = false, wordsSoFar: Int = 0, promptsSoFar: Int = 0,
    secondsSincePrompt: TimeInterval? = nil
  ) {
    self.now = now
    self.pauseLength = pauseLength
    self.speechDensity = speechDensity
    self.awaitingFinishedReply = awaitingFinishedReply
    self.wordsSoFar = wordsSoFar
    self.promptsSoFar = promptsSoFar
    self.secondsSincePrompt = secondsSincePrompt
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

  /// Every utterance end is a check. Pause ticks are throttled to the minimum interval.
  /// The largest of goodMoment and each cue scaled by its configured weight.
  public func momentScore(_ answers: JevAnswers) -> Double {
    moment(answers).score
  }

  /// The score and the cue that produced it, nil when goodMoment itself is the largest.
  func moment(_ answers: JevAnswers) -> (score: Double, cue: String?) {
    var best: (score: Double, cue: String?) = (answers.goodMoment.probability, nil)
    for (name, weight) in config.cueWeights {
      guard let probability = answers.cues[name] else { continue }
      let score = min(1, probability * weight)
      if score > best.score { best = (score, name) }
    }
    return best
  }

  /// The kind to ask: the opening cue's kind when configured, else Jev's intervention choice.
  public func kind(for answers: JevAnswers) -> InterventionKind {
    if let cue = moment(answers).cue, let kind = config.cueKinds[cue] { return kind }
    return answers.intervention.choice
  }

  /// Whether to ask Jev at `now`. Every utterance end is a check. In silence the schedule
  /// fires once per offset, then the end check after the finished question. Taking a check
  /// moves the schedule on even when the call fails.
  public mutating func takeCheck(now: TimeInterval, speechEnd: TimeInterval, utteranceEnded: Bool)
    -> Bool
  {
    if !utteranceEnded {
      guard let due = nextCheck(speechEnd: speechEnd), due <= now else { return false }
    }
    lastCheckAt = now
    return true
  }

  /// When the next silence check falls after speech ended at `speechEnd`: the schedule, then
  /// the long-silence check, then nil until speech resumes.
  public func nextCheck(speechEnd: TimeInterval) -> TimeInterval? {
    let last = lastCheckAt ?? -.infinity
    if finishedAskedAt != nil {
      return max(speechEnd, last) + config.endSilence
    }
    let offsets = config.silenceChecks + [config.longSilence]
    return offsets.map { speechEnd + $0 }.filter { $0 > last }.min()
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
      if signals.now - signals.pauseLength > asked {
        finishedAskedAt = nil
      }
      return .wait
    }

    if signals.pauseLength >= config.longSilence
      || answers.seemsFinished.probability >= config.finished.probability
    {
      finishedAskedAt = signals.now
      return .askIfFinished
    }

    guard momentScore(answers) >= config.speak.probability,
      answers.intervention.confidence >= config.speak.confidence
    else { return .wait }

    if signals.now < config.warmUp { return .wait }
    if let last = lastPromptAt, signals.now - last < floor(for: answers, signals: signals) {
      return .wait
    }

    lastPromptAt = signals.now
    return .prompt(kind(for: answers))
  }
}
