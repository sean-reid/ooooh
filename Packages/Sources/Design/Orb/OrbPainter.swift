import SwiftUI

/// Orb colors are fixed per appearance rather than adaptive, so the painter can mix them.
struct OrbTint {
  var core: Color
  var warm: Color
  var amber: Color
  var rim: Color
  var glow: Color
  var glowAlpha: Double
  var glowBlend: GraphicsContext.BlendMode
  var sheen: Double
  var rimStart: CGFloat
  var ash: Color

  init(_ scheme: ColorScheme) {
    amber = Color(red: 0.980, green: 0.741, blue: 0.345)
    switch scheme {
    case .dark:
      core = Color(red: 1.0, green: 0.960, blue: 0.860)
      warm = Color(red: 1.0, green: 0.860, blue: 0.560)
      rim = Color(red: 0.930, green: 0.570, blue: 0.170)
      glow = amber
      glowAlpha = 0.5
      glowBlend = .normal
      sheen = 1
      rimStart = 0.78
      ash = Color(red: 0.300, green: 0.290, blue: 0.280)
    default:
      core = Color(red: 1.0, green: 0.950, blue: 0.800)
      warm = Color(red: 1.0, green: 0.820, blue: 0.450)
      rim = Color(red: 0.860, green: 0.470, blue: 0.100)
      glow = Color(red: 0.930, green: 0.660, blue: 0.340)
      glowAlpha = 0.7
      glowBlend = .multiply
      sheen = 0
      rimStart = 0.84
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
    let base = min(size.width, size.height) * 0.26 * (1 + 0.12 * frame.breath)
    let body = OrbGeometry.blob(
      center: center, radius: base, clock: frame.clock, drift: pose.drift, breath: frame.breath,
      stretch: pose.stretch)
    let halo = OrbGeometry.blob(
      center: center, radius: base * 1.9, clock: frame.clock * 0.7, drift: pose.drift * 0.5,
      breath: 0, stretch: pose.stretch)
    let under = OrbGeometry.blob(
      center: center, radius: base * 1.14, clock: frame.clock, drift: pose.drift,
      breath: frame.breath, stretch: pose.stretch)
    let lit = 1 - pose.dim
    let dim = pose.dim * 0.85
    let bodyAlpha = 1 - 0.3 * pose.dim

    var glowContext = context
    glowContext.blendMode = tint.glowBlend
    glowContext.drawLayer { layer in
      layer.addFilter(.blur(radius: base * 0.3))
      layer.fill(
        halo,
        with: .radialGradient(
          Gradient(stops: [
            .init(color: tint.glow.opacity(tint.glowAlpha * pose.glow), location: 0),
            .init(color: tint.glow.opacity(0.45 * tint.glowAlpha * pose.glow), location: 0.4),
            .init(color: tint.glow.opacity(0.12 * tint.glowAlpha * pose.glow), location: 0.75),
            .init(color: tint.glow.opacity(0), location: 1),
          ]),
          center: center, startRadius: base * 0.4, endRadius: base * 1.9))
    }

    context.drawLayer { layer in
      layer.addFilter(.blur(radius: base * 0.12))
      layer.fill(
        under,
        with: .radialGradient(
          Gradient(stops: [
            .init(color: tint.glow.opacity(0.55 * lit), location: 0),
            .init(color: tint.glow.opacity(0.35 * lit), location: 0.8),
            .init(color: tint.glow.opacity(0), location: 1),
          ]),
          center: center, startRadius: 0, endRadius: base * 1.14))
    }

    let coreCenter = CGPoint(x: center.x - base * 0.06, y: center.y - base * 0.08)
    context.fill(
      body,
      with: .radialGradient(
        Gradient(stops: [
          .init(color: tint.core.mix(with: tint.ash, by: dim).opacity(bodyAlpha), location: 0),
          .init(color: tint.warm.mix(with: tint.ash, by: dim).opacity(bodyAlpha), location: 0.42),
          .init(
            color: tint.amber.mix(with: tint.ash, by: dim).opacity(bodyAlpha),
            location: tint.rimStart),
          .init(color: tint.rim.mix(with: tint.ash, by: dim).opacity(bodyAlpha), location: 1),
        ]),
        center: coreCenter, startRadius: 0, endRadius: base * 1.25))

    context.drawLayer { layer in
      layer.clip(to: body)
      layer.addFilter(.blur(radius: base * 0.22))
      let highlight = Path(
        ellipseIn: CGRect(
          x: coreCenter.x - base * 0.4, y: coreCenter.y - base * 0.32, width: base * 0.8,
          height: base * 0.64))
      layer.fill(
        highlight, with: .color(.white.opacity((0.1 + 0.15 * pose.glow) * lit * tint.sheen)))
    }

    guard let grain else { return }
    var grainContext = context
    grainContext.blendMode = .softLight
    grainContext.opacity = 0.12 + 0.1 * pose.dim
    grainContext.drawLayer { layer in
      layer.clip(to: body)
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
      layer.blendMode = .destinationIn
      layer.fill(
        body,
        with: .radialGradient(
          Gradient(stops: [
            .init(color: .white.opacity(0.05), location: 0),
            .init(color: .white.opacity(0.35), location: 0.55),
            .init(color: .white, location: 1),
          ]),
          center: center, startRadius: 0, endRadius: base * 1.1))
    }
  }
}
