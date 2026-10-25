import SwiftUI

enum OrbGeometry {
  static func blob(
    center: CGPoint, radius: CGFloat, clock: Double, drift: Double, breath: Double,
    stretch: Double
  ) -> Path {
    let count = 48
    var points: [CGPoint] = []
    points.reserveCapacity(count)
    for i in 0..<count {
      let theta = Double(i) / Double(count) * 2 * .pi
      let wobble =
        drift
        * (0.055 * sin(2 * theta + clock * 0.70) + 0.040 * sin(3 * theta - clock * 0.47 + 1.3)
          + 0.025 * sin(5 * theta + clock * 1.10 + 2.1))
      let voice = breath * 0.035 * sin(4 * theta - clock * 2.3 + 0.7)
      let r = radius * (1 + wobble + voice)
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
