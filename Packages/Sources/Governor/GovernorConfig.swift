import Foundation
import State

/// Thresholds and ranges. Served by the Worker, cached on device, versioned.
public struct GovernorConfig: Codable, Equatable, Sendable {
  public var version: Int
  public var floor: FloorRange
  public var speak: Thresholds
  public var finished: Thresholds
  public var command: Thresholds
  public var densityWindow: TimeInterval
  public var endSilence: TimeInterval
  /// Pause lengths at which the loop asks Jev during silence. After the last, nothing until speech resumes.
  public var silenceChecks: [TimeInterval]
  /// How long the pause after an utterance has to hold before an armed decision speaks.
  public var armingDelay: TimeInterval
  /// Weight per cue name. The moment score is the largest weighted cue; an unweighted cue is ignored.
  public var cueWeights: [String: Double]
  /// The kind each cue asks for. A cue with no kind cannot open the gate.
  public var cueKinds: [String: InterventionKind]

  public init(
    version: Int,
    floor: FloorRange,
    speak: Thresholds,
    finished: Thresholds,
    command: Thresholds,
    densityWindow: TimeInterval,
    endSilence: TimeInterval,
    silenceChecks: [TimeInterval] = [5, 11, 20],
    armingDelay: TimeInterval = 1.5,
    cueWeights: [String: Double] = [:],
    cueKinds: [String: InterventionKind] = [:]
  ) {
    self.version = version
    self.floor = floor
    self.speak = speak
    self.finished = finished
    self.command = command
    self.densityWindow = densityWindow
    self.endSilence = endSilence
    self.silenceChecks = silenceChecks
    self.armingDelay = armingDelay
    self.cueWeights = cueWeights
    self.cueKinds = cueKinds
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decode(Int.self, forKey: .version)
    floor = try c.decode(FloorRange.self, forKey: .floor)
    speak = try c.decode(Thresholds.self, forKey: .speak)
    finished = try c.decode(Thresholds.self, forKey: .finished)
    command = try c.decode(Thresholds.self, forKey: .command)
    densityWindow = try c.decode(TimeInterval.self, forKey: .densityWindow)
    endSilence = try c.decode(TimeInterval.self, forKey: .endSilence)
    silenceChecks =
      try c.decodeIfPresent([TimeInterval].self, forKey: .silenceChecks) ?? [5, 11, 20]
    armingDelay = try c.decodeIfPresent(TimeInterval.self, forKey: .armingDelay) ?? 1.5
    cueWeights = try c.decodeIfPresent([String: Double].self, forKey: .cueWeights) ?? [:]
    cueKinds = try c.decodeIfPresent([String: InterventionKind].self, forKey: .cueKinds) ?? [:]
  }

  public struct FloorRange: Codable, Equatable, Sendable {
    public var min: TimeInterval
    public var max: TimeInterval

    public init(min: TimeInterval, max: TimeInterval) {
      self.min = min
      self.max = max
    }
  }

  public struct Thresholds: Codable, Equatable, Sendable {
    public var probability: Double
    public var confidence: Double

    public init(probability: Double, confidence: Double) {
      self.probability = probability
      self.confidence = confidence
    }
  }

  /// The cue, first by name, that asks for `kind`; nil when the set has none for it.
  public func cue(for kind: InterventionKind) -> String? {
    cueKinds.filter { $0.value == kind }.keys.sorted().first
  }

  /// Starting point before any calibration. The eval replaces these numbers.
  public static var initial: GovernorConfig {
    GovernorConfig(
      version: 6,
      floor: FloorRange(min: 30, max: 120),
      speak: Thresholds(probability: 0.9, confidence: 0),
      finished: Thresholds(probability: 0.6, confidence: 0.7),
      command: Thresholds(probability: 0.9, confidence: 0.7),
      densityWindow: 120,
      endSilence: 30,
      silenceChecks: [5, 11, 20],
      armingDelay: 1.5,
      cueWeights: [
        "hangingQuestion": 1.0, "trailsOff": 1.38, "unnamedDecision": 1.125,
        "realisation": 1.0, "threadShift": 1.0, "untestedClaim": 1.125,
      ],
      cueKinds: [
        "hangingQuestion": .clarify, "trailsOff": .deepen, "unnamedDecision": .decide,
        "realisation": .reflect, "threadShift": .summarize, "untestedClaim": .challenge,
      ]
    )
  }
}
