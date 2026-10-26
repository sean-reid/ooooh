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
    amber = Palette.amberShade.color
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

/// Layer radii as multiples of the body radius, and gradient stops as (location, alpha) pairs.
enum OrbLayers {
  static let body = 0.26
  static let breathGrow = 0.12
  static let halo = (radius: 1.9, clock: 0.7, drift: 0.5, blur: 0.3, start: 0.4)
  static let haloStops: [(location: Double, alpha: Double)] = [
    (0, 1), (0.4, 0.45), (0.75, 0.12), (1, 0),
  ]
  static let under = (radius: 1.14, blur: 0.12)
  static let underStops: [(location: Double, alpha: Double)] = [(0, 0.55), (0.8, 0.35), (1, 0)]
  static let core = (x: 0.06, y: 0.08, end: 1.25, warm: 0.42)
  static let sheen = (blur: 0.22, width: 0.4, height: 0.32, floor: 0.1, glow: 0.15)
  static let grain = (alpha: 0.12, end: 1.1)
  static let grainFade: [(location: Double, alpha: Double)] = [(0, 0.05), (0.55, 0.35), (1, 1)]
}

struct OrbPainter {
  var frame: OrbFrame
  var tint: OrbTint

  func paint(in context: inout GraphicsContext, size: CGSize, grain: GraphicsContext.ResolvedImage?)
  {
    let pose = frame.pose
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let base =
      min(size.width, size.height) * OrbLayers.body * (1 + OrbLayers.breathGrow * frame.breath)
    let body = OrbGeometry.blob(
      center: center, radius: base, clock: frame.clock, drift: pose.drift, breath: frame.breath,
      stretch: pose.stretch)
    let halo = OrbGeometry.blob(
      center: center, radius: base * OrbLayers.halo.radius,
      clock: frame.clock * OrbLayers.halo.clock, drift: pose.drift * OrbLayers.halo.drift,
      breath: 0, stretch: pose.stretch)
    let under = OrbGeometry.blob(
      center: center, radius: base * OrbLayers.under.radius, clock: frame.clock,
      drift: pose.drift, breath: frame.breath, stretch: pose.stretch)
    let lit = 1 - pose.dim
    let dim = pose.dim * 0.85
    let bodyAlpha = 1 - 0.3 * pose.dim

    var glowContext = context
    glowContext.blendMode = tint.glowBlend
    glowContext.drawLayer { layer in
      layer.addFilter(.blur(radius: base * OrbLayers.halo.blur))
      layer.fill(
        halo,
        with: .radialGradient(
          gradient(OrbLayers.haloStops) {
            tint.glow.opacity($0 * tint.glowAlpha * pose.glow)
          },
          center: center, startRadius: base * OrbLayers.halo.start,
          endRadius: base * OrbLayers.halo.radius))
    }

    context.drawLayer { layer in
      layer.addFilter(.blur(radius: base * OrbLayers.under.blur))
      layer.fill(
        under,
        with: .radialGradient(
          gradient(OrbLayers.underStops) { tint.glow.opacity($0 * lit) },
          center: center, startRadius: 0, endRadius: base * OrbLayers.under.radius))
    }

    let coreCenter = CGPoint(
      x: center.x - base * OrbLayers.core.x, y: center.y - base * OrbLayers.core.y)
    context.fill(
      body,
      with: .radialGradient(
        Gradient(stops: [
          .init(color: tint.core.mix(with: tint.ash, by: dim).opacity(bodyAlpha), location: 0),
          .init(
            color: tint.warm.mix(with: tint.ash, by: dim).opacity(bodyAlpha),
            location: OrbLayers.core.warm),
          .init(
            color: tint.amber.mix(with: tint.ash, by: dim).opacity(bodyAlpha),
            location: tint.rimStart),
          .init(color: tint.rim.mix(with: tint.ash, by: dim).opacity(bodyAlpha), location: 1),
        ]),
        center: coreCenter, startRadius: 0, endRadius: base * OrbLayers.core.end))

    context.drawLayer { layer in
      layer.clip(to: body)
      layer.addFilter(.blur(radius: base * OrbLayers.sheen.blur))
      let highlight = Path(
        ellipseIn: CGRect(
          x: coreCenter.x - base * OrbLayers.sheen.width,
          y: coreCenter.y - base * OrbLayers.sheen.height,
          width: base * OrbLayers.sheen.width * 2, height: base * OrbLayers.sheen.height * 2))
      layer.fill(
        highlight,
        with: .color(
          .white.opacity(
            (OrbLayers.sheen.floor + OrbLayers.sheen.glow * pose.glow) * lit * tint.sheen)))
    }

    guard let grain else { return }
    var grainContext = context
    grainContext.blendMode = .softLight
    grainContext.opacity = OrbLayers.grain.alpha + 0.1 * pose.dim
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
          gradient(OrbLayers.grainFade) { .white.opacity($0) },
          center: center, startRadius: 0, endRadius: base * OrbLayers.grain.end))
    }
  }

  private func gradient(
    _ stops: [(location: Double, alpha: Double)], _ color: (Double) -> Color
  ) -> Gradient {
    Gradient(stops: stops.map { .init(color: color($0.alpha), location: $0.location) })
  }
}
