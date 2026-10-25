import SwiftUI

/// Orb colors are fixed per appearance rather than adaptive, so the painter can mix them.
struct OrbTint {
  var core: Color
  var mid: Color
  var rim: Color
  var edge: Color
  var glow: Color
  var ash: Color

  init(_ scheme: ColorScheme) {
    mid = Color(red: 0.980, green: 0.741, blue: 0.345)
    switch scheme {
    case .dark:
      core = Color(red: 1.0, green: 0.930, blue: 0.740)
      rim = Color(red: 0.839, green: 0.459, blue: 0.125)
      edge = Color(red: 0.549, green: 0.259, blue: 0.067)
      glow = mid
      ash = Color(red: 0.300, green: 0.290, blue: 0.280)
    default:
      core = Color(red: 1.0, green: 0.940, blue: 0.760)
      rim = Color(red: 0.880, green: 0.520, blue: 0.160)
      edge = Color(red: 0.760, green: 0.400, blue: 0.110)
      glow = Color(red: 0.960, green: 0.640, blue: 0.180)
      ash = Color(red: 0.780, green: 0.760, blue: 0.730)
    }
  }
}

struct OrbPainter {
  var frame: OrbFrame
  var tint: OrbTint

  func paint(in context: inout GraphicsContext, size: CGSize, grain: GraphicsContext.ResolvedImage?)
  {
    let pose = frame.pose
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let base = min(size.width, size.height) * 0.27 * (1 + 0.12 * frame.breath)
    let body = OrbGeometry.blob(
      center: center, radius: base, clock: frame.clock, drift: pose.drift, breath: frame.breath,
      stretch: pose.stretch)
    let halo = OrbGeometry.blob(
      center: center, radius: base * 1.6, clock: frame.clock * 0.7, drift: pose.drift * 0.6,
      breath: 0, stretch: pose.stretch)
    let lit = 1 - pose.dim
    let bodyAlpha = 1 - 0.3 * pose.dim

    context.drawLayer { layer in
      layer.addFilter(.blur(radius: base * 0.24))
      layer.fill(
        halo,
        with: .radialGradient(
          Gradient(stops: [
            .init(color: tint.glow.opacity(0.55 * pose.glow), location: 0),
            .init(color: tint.glow.opacity(0.18 * pose.glow), location: 0.55),
            .init(color: tint.glow.opacity(0), location: 1),
          ]),
          center: center, startRadius: base * 0.5, endRadius: base * 1.7))
    }

    let coreCenter = CGPoint(x: center.x - base * 0.22, y: center.y - base * 0.26)
    context.fill(
      body,
      with: .radialGradient(
        Gradient(stops: [
          .init(color: tint.core.mix(with: tint.ash, by: pose.dim).opacity(bodyAlpha), location: 0),
          .init(
            color: tint.mid.mix(with: tint.ash, by: pose.dim).opacity(bodyAlpha), location: 0.48),
          .init(
            color: tint.rim.mix(with: tint.ash, by: pose.dim).opacity(bodyAlpha), location: 0.9),
          .init(color: tint.edge.mix(with: tint.ash, by: pose.dim).opacity(bodyAlpha), location: 1),
        ]),
        center: coreCenter, startRadius: 0, endRadius: base * 1.3))

    context.drawLayer { layer in
      layer.clip(to: body)
      layer.addFilter(.blur(radius: base * 0.16))
      let highlight = Path(
        ellipseIn: CGRect(
          x: coreCenter.x - base * 0.34, y: coreCenter.y - base * 0.26, width: base * 0.68,
          height: base * 0.52))
      layer.fill(highlight, with: .color(.white.opacity((0.14 + 0.22 * pose.glow) * lit)))
    }

    guard let grain else { return }
    context.drawLayer { layer in
      layer.clip(to: body)
      layer.blendMode = .softLight
      layer.opacity = 0.32
      let step = CGFloat(OrbGrain.tile) * 0.75
      var y: CGFloat = 0
      while y < size.height {
        var x: CGFloat = 0
        while x < size.width {
          layer.draw(grain, in: CGRect(x: x, y: y, width: step, height: step))
          x += step
        }
        y += step
      }
    }
  }
}
