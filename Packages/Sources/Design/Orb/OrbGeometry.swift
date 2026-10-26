import SwiftUI

enum OrbGeometry {
  static let count = 48
  /// Each wobble term: amplitude, harmonic, clock rate, phase. The voice term scales with breath.
  static let wobble: [(amplitude: Double, harmonic: Double, rate: Double, phase: Double)] = [
    (0.055, 2, 0.70, 0), (0.040, 3, -0.47, 1.3), (0.025, 5, 1.10, 2.1),
  ]
  static let voice = (amplitude: 0.035, harmonic: 4.0, rate: -2.3, phase: 0.7)

  static func blob(
    center: CGPoint, radius: CGFloat, clock: Double, drift: Double, breath: Double,
    stretch: Double
  ) -> Path {
    var points: [CGPoint] = []
    points.reserveCapacity(count)
    for i in 0..<count {
      let theta = Double(i) / Double(count) * 2 * .pi
      var wobble = 0.0
      for term in Self.wobble {
        wobble += term.amplitude * sin(term.harmonic * theta + clock * term.rate + term.phase)
      }
      let voice =
        breath * Self.voice.amplitude
        * sin(Self.voice.harmonic * theta + clock * Self.voice.rate + Self.voice.phase)
      let r = radius * (1 + wobble * drift + voice)
      let x = cos(theta) * r / sqrt(stretch)
      let y = sin(theta) * r * sqrt(stretch)
      points.append(CGPoint(x: center.x + x, y: center.y + y))
    }
    return smoothClosed(points)
  }

  /// Catmull-Rom through every point, as cubic Beziers.
  static func smoothClosed(_ points: [CGPoint]) -> Path {
    var path = Path()
    let n = points.count
    guard n > 2 else { return path }
    path.move(to: points[0])
    for i in 0..<n {
      let p0 = points[(i + n - 1) % n]
      let p1 = points[i]
      let p2 = points[(i + 1) % n]
      let p3 = points[(i + 2) % n]
      let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
      let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
      path.addCurve(to: p2, control1: c1, control2: c2)
    }
    path.closeSubpath()
    return path
  }
}
