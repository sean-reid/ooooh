import Foundation

/// Thresholds and ranges. Served by the Worker, cached on device, versioned.
public struct GovernorConfig: Codable, Equatable, Sendable {
  public var version: Int
  public var floor: FloorRange
  public var speak: Thresholds
  public var finished: Thresholds
  public var command: Thresholds
  public var densityWindow: TimeInterval
  public var endSilence: TimeInterval
  public var checkPause: TimeInterval
  public var minCheckInterval: TimeInterval
  /// Weight per cue name. The moment score is the largest of goodMoment and each weighted cue.
  public var cueWeights: [String: Double]

  public init(
    version: Int,
    floor: FloorRange,
    speak: Thresholds,
    finished: Thresholds,
    command: Thresholds,
    densityWindow: TimeInterval,
    endSilence: TimeInterval,
    checkPause: TimeInterval,
    minCheckInterval: TimeInterval,
    cueWeights: [String: Double] = [:]
  ) {
    self.version = version
    self.floor = floor
    self.speak = speak
    self.finished = finished
    self.command = command
    self.densityWindow = densityWindow
    self.endSilence = endSilence
    self.checkPause = checkPause
    self.minCheckInterval = minCheckInterval
    self.cueWeights = cueWeights
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
    checkPause = try c.decode(TimeInterval.self, forKey: .checkPause)
    minCheckInterval = try c.decode(TimeInterval.self, forKey: .minCheckInterval)
    cueWeights = try c.decodeIfPresent([String: Double].self, forKey: .cueWeights) ?? [:]
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

  /// Starting point before any calibration. The eval replaces these numbers.
  public static let initial = GovernorConfig(
    version: 1,
    floor: FloorRange(min: 30, max: 120),
    speak: Thresholds(probability: 0.75, confidence: 0.6),
    finished: Thresholds(probability: 0.9, confidence: 0.7),
    command: Thresholds(probability: 0.9, confidence: 0.7),
    densityWindow: 120,
    endSilence: 30,
    checkPause: 2,
    minCheckInterval: 3,
    cueWeights: [
      "hangingQuestion": 1.0, "repeatsPoint": 1.0, "trailsOff": 0.8, "contradictsEarlier": 1.0,
      "unnamedDecision": 1.0,
    ]
  )
}
