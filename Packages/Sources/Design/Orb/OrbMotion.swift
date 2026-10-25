import Foundation

/// Everything one frame of the orb is drawn from.
struct OrbFrame {
  var clock: TimeInterval
  var breath: Double
  var pose: OrbPose
}

/// Per-phase look, smoothed over time so a phase change never snaps.
struct OrbPose {
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
    stretch += (target.stretch - stretch) * fraction
    glow += (target.glow - glow) * fraction
    drift += (target.drift - drift) * fraction
    dim += (target.dim - dim) * fraction
    speed += (target.speed - speed) * fraction
  }
}

/// Low-pass filters the voice level and the phase look between frames.
@MainActor
final class OrbMotion {
  private var frame = OrbFrame(clock: 0, breath: 0, pose: .target(for: .resting))
  private var lastDate: Date?

  nonisolated init() {}

  func advance(to date: Date, level: Double, phase: OrbPhase) -> OrbFrame {
    defer { lastDate = date }
    let level = min(max(level, 0), 1)
    guard let last = lastDate else {
      frame.breath = level
      frame.pose = .target(for: phase)
      return frame
    }
    let dt = min(max(date.timeIntervalSince(last), 0), 0.1)
    let tau = level > frame.breath ? 0.12 : 0.45
    frame.breath += (level - frame.breath) * (1 - exp(-dt / tau))
    frame.pose.approach(.target(for: phase), by: 1 - exp(-dt / 0.3))
    frame.clock += dt * frame.pose.speed
    return frame
  }

  nonisolated static func still(at time: TimeInterval, level: Double, phase: OrbPhase) -> OrbFrame {
    OrbFrame(clock: time, breath: min(max(level, 0), 1), pose: .target(for: phase))
  }
}
