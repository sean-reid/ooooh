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

  public init(
    version: Int,
    floor: FloorRange,
    speak: Thresholds,
    finished: Thresholds,
    command: Thresholds,
    densityWindow: TimeInterval,
    endSilence: TimeInterval,
    checkPause: TimeInterval,
    minCheckInterval: TimeInterval
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
    minCheckInterval: 3
  )
}
