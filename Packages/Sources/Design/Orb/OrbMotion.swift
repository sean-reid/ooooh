import Foundation

/// Everything one frame of the orb is drawn from.
struct OrbFrame {
  var clock: TimeInterval
  var breath: Double
  var pose: OrbPose
}

/// Per-phase look, smoothed over time so a phase change never snaps.
struct OrbPose: Equatable {
  var stretch: Double
  var glow: Double
  var drift: Double
  var dim: Double
  var speed: Double

  static func target(for phase: OrbPhase) -> OrbPose {
    switch phase {
    case .resting: OrbPose(stretch: 1, glow: 0.45, drift: 0.5, dim: 0, speed: 0.6)
    case .listening: OrbPose(stretch: 1, glow: 0.7, drift: 1, dim: 0, speed: 1)
    case .aboutToSpeak: OrbPose(stretch: 1.18, glow: 1, drift: 0.55, dim: 0, speed: 0.8)
    case .speaking: OrbPose(stretch: 1.05, glow: 0.9, drift: 0.9, dim: 0, speed: 1.4)
    case .offline: OrbPose(stretch: 1, glow: 0, drift: 0, dim: 1, speed: 0)
    }
  }

  static let still = OrbPose(stretch: 1, glow: 0.7, drift: 0.4, dim: 0, speed: 0)

  mutating func approach(_ target: OrbPose, by fraction: Double) {
    stretch = Self.ease(stretch, to: target.stretch, by: fraction)
    glow = Self.ease(glow, to: target.glow, by: fraction)
    drift = Self.ease(drift, to: target.drift, by: fraction)
    dim = Self.ease(dim, to: target.dim, by: fraction)
    speed = Self.ease(speed, to: target.speed, by: fraction)
  }

  /// One low-pass step; it lands on the target once within 0.002 so equality is reachable.
  static func ease(_ value: Double, to target: Double, by fraction: Double) -> Double {
    let next = value + (target - value) * fraction
    return abs(target - next) < 0.002 ? target : next
  }
}

/// Low-pass filters the voice level and the phase look between frames.
@MainActor
final class OrbMotion {
  private var frame = OrbFrame(clock: 0, breath: 0, pose: .target(for: .resting))
  private var lastDate: Date?
  /// Frames advanced so far, which is what the timeline drew.
  private(set) var frames = 0
  /// True once the frame has settled where the next one would repeat it.
  private(set) var rests = false

  nonisolated init() {}

  func advance(to date: Date, level: Double, phase: OrbPhase) -> OrbFrame {
    defer { lastDate = date }
    frames += 1
    let level = min(max(level, 0), 1)
    let target = Self.target(for: phase, level: level)
    guard let last = lastDate else {
      frame.breath = level
      frame.pose = target
      rests = target.speed == 0
      return frame
    }
    let dt = min(max(date.timeIntervalSince(last), 0), 0.1)
    let tau = level > frame.breath ? 0.12 : 0.45
    frame.breath = OrbPose.ease(frame.breath, to: level, by: 1 - exp(-dt / tau))
    frame.pose.approach(target, by: 1 - exp(-dt / 0.3))
    frame.clock += dt * frame.pose.speed
    rests = frame.pose == target && frame.breath == level && target.speed == 0
    return frame
  }

  /// Silence while resting also stops the clock, so the drift halts instead of running forever.
  static func target(for phase: OrbPhase, level: Double) -> OrbPose {
    var pose = OrbPose.target(for: phase)
    if phase == .resting && level <= 0 { pose.speed = 0 }
    return pose
  }

  nonisolated static func still(at time: TimeInterval, level: Double, phase: OrbPhase) -> OrbFrame {
    OrbFrame(clock: time, breath: min(max(level, 0), 1), pose: .target(for: phase))
  }
}
