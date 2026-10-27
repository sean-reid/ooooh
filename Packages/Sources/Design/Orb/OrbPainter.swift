import SwiftUI

/// Orb colors are fixed per appearance rather than adaptive, so the painter can mix them.
struct OrbTint {
  var scheme: ColorScheme
  var core: Palette.Shade
  var warm: Palette.Shade
  var rim: Palette.Shade
  var glow: Palette.Shade
  var ash: Palette.Shade
  var glowAlpha: Double
  var glowBlend: GraphicsContext.BlendMode
  var sheen: Double
  var rimStart: CGFloat
  var amber: Palette.Shade { Palette.amberShade }

  init(_ scheme: ColorScheme) {
    self.scheme = scheme
    switch scheme {
    case .dark:
      core = Palette.Shade(1.0, 0.960, 0.860)
      warm = Palette.Shade(1.0, 0.860, 0.560)
      rim = Palette.Shade(0.930, 0.570, 0.170)
      glow = Palette.amberShade
      glowAlpha = 0.5
      glowBlend = .normal
      sheen = 1
      rimStart = 0.78
      ash = Palette.Shade(0.300, 0.290, 0.280)
    default:
      core = Palette.Shade(1.0, 0.950, 0.800)
      warm = Palette.Shade(1.0, 0.820, 0.450)
      rim = Palette.Shade(0.860, 0.470, 0.100)
      glow = Palette.Shade(0.930, 0.660, 0.340)
      glowAlpha = 0.7
      glowBlend = .multiply
      sheen = 0
      rimStart = 0.84
      ash = Palette.Shade(0.780, 0.760, 0.730)
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

  /// The layers in paint order.
  enum Layer: String, CaseIterable {
    case halo, under, body, sheen, grain
  }

  /// Resolved once per frame by the canvas: the grain tile, and the halo disc when it is cached.
  struct Images {
    var grain: GraphicsContext.ResolvedImage?
    var halo: GraphicsContext.ResolvedImage?
  }

  /// What every layer measures from: the body radius after breath, and the body outline.
  struct Scene {
    var size: CGSize
    var center: CGPoint
    var base: CGFloat
    var body: Path

    init(frame: OrbFrame, size: CGSize) {
      self.size = size
      center = CGPoint(x: size.width / 2, y: size.height / 2)
      base =
        min(size.width, size.height) * OrbLayers.body * (1 + OrbLayers.breathGrow * frame.breath)
      body = OrbGeometry.blob(
        center: center, radius: base, clock: frame.clock, drift: frame.pose.drift,
        breath: frame.breath, stretch: frame.pose.stretch)
    }
  }

  func paint(in context: inout GraphicsContext, size: CGSize, images: Images) {
    let scene = Scene(frame: frame, size: size)
    for layer in Layer.allCases {
      paint(layer, scene, in: &context, images: images)
    }
  }

  func paint(_ layer: Layer, in context: inout GraphicsContext, size: CGSize, images: Images) {
    paint(layer, Scene(frame: frame, size: size), in: &context, images: images)
  }

  private func paint(
    _ layer: Layer, _ scene: Scene, in context: inout GraphicsContext, images: Images
  ) {
    switch layer {
    case .halo: halo(scene, in: &context, disc: images.halo)
    case .under: under(scene, in: &context)
    case .body: body(scene, in: &context)
    case .sheen: sheen(scene, in: &context)
    case .grain: if let grain = images.grain { self.grain(scene, in: &context, tile: grain) }
    }
  }

  private func halo(
    _ scene: Scene, in context: inout GraphicsContext, disc: GraphicsContext.ResolvedImage?
  ) {
    let pose = frame.pose
    guard pose.glow > 0 else { return }
    guard let disc else {
      Self.blurredHalo(
        in: &context, center: scene.center, base: scene.base, tint: tint, pose: pose,
        clock: frame.clock)
      return
    }
    let half = scene.base * OrbHalo.extent
    var glowContext = context
    glowContext.blendMode = tint.glowBlend
    glowContext.opacity = pose.glow
    glowContext.draw(
      disc,
      in: CGRect(
        x: scene.center.x - half, y: scene.center.y - half, width: 2 * half, height: 2 * half))
  }

  /// The halo drawn and blurred in place: what OrbHalo caches, and the fallback when it cannot.
  static func blurredHalo(
    in context: inout GraphicsContext, center: CGPoint, base: CGFloat, tint: OrbTint,
    pose: OrbPose, clock: TimeInterval
  ) {
    let halo = OrbGeometry.blob(
      center: center, radius: base * OrbLayers.halo.radius, clock: clock * OrbLayers.halo.clock,
      drift: pose.drift * OrbLayers.halo.drift, breath: 0, stretch: pose.stretch)
    let glow = tint.glow.color
    var glowContext = context
    glowContext.blendMode = tint.glowBlend
    glowContext.drawLayer { layer in
      layer.addFilter(.blur(radius: base * OrbLayers.halo.blur))
      layer.fill(
        halo,
        with: .radialGradient(
          gradient(OrbLayers.haloStops) { glow.opacity($0 * tint.glowAlpha * pose.glow) },
          center: center, startRadius: base * OrbLayers.halo.start,
          endRadius: base * OrbLayers.halo.radius))
    }
  }

  private func under(_ scene: Scene, in context: inout GraphicsContext) {
    let pose = frame.pose
    guard pose.dim < 1 else { return }
    let under = OrbGeometry.blob(
      center: scene.center, radius: scene.base * OrbLayers.under.radius, clock: frame.clock,
      drift: pose.drift, breath: frame.breath, stretch: pose.stretch)
    let lit = 1 - pose.dim
    let glow = tint.glow.color
    context.drawLayer { layer in
      layer.addFilter(.blur(radius: scene.base * OrbLayers.under.blur))
      layer.fill(
        under,
        with: .radialGradient(
          Self.gradient(OrbLayers.underStops) { glow.opacity($0 * lit) },
          center: scene.center, startRadius: 0, endRadius: scene.base * OrbLayers.under.radius))
    }
  }

  private func body(_ scene: Scene, in context: inout GraphicsContext) {
    let dim = frame.pose.dim * 0.85
    let bodyAlpha = 1 - 0.3 * frame.pose.dim
    let ash = tint.ash.color
    context.fill(
      scene.body,
      with: .radialGradient(
        Gradient(stops: [
          .init(color: tint.core.color.mix(with: ash, by: dim).opacity(bodyAlpha), location: 0),
          .init(
            color: tint.warm.color.mix(with: ash, by: dim).opacity(bodyAlpha),
            location: OrbLayers.core.warm),
          .init(
            color: tint.amber.color.mix(with: ash, by: dim).opacity(bodyAlpha),
            location: tint.rimStart),
          .init(color: tint.rim.color.mix(with: ash, by: dim).opacity(bodyAlpha), location: 1),
        ]),
        center: coreCenter(scene), startRadius: 0, endRadius: scene.base * OrbLayers.core.end))
  }

  private func sheen(_ scene: Scene, in context: inout GraphicsContext) {
    let pose = frame.pose
    let alpha =
      (OrbLayers.sheen.floor + OrbLayers.sheen.glow * pose.glow) * (1 - pose.dim) * tint.sheen
    guard alpha > 0 else { return }
    let coreCenter = coreCenter(scene)
    let base = scene.base
    context.drawLayer { layer in
      layer.clip(to: scene.body)
      layer.addFilter(.blur(radius: base * OrbLayers.sheen.blur))
      let highlight = Path(
        ellipseIn: CGRect(
          x: coreCenter.x - base * OrbLayers.sheen.width,
          y: coreCenter.y - base * OrbLayers.sheen.height,
          width: base * OrbLayers.sheen.width * 2, height: base * OrbLayers.sheen.height * 2))
      layer.fill(highlight, with: .color(.white.opacity(alpha)))
    }
  }

  private func grain(
    _ scene: Scene, in context: inout GraphicsContext, tile: GraphicsContext.ResolvedImage
  ) {
    var grainContext = context
    grainContext.blendMode = .softLight
    grainContext.opacity = OrbLayers.grain.alpha + 0.1 * frame.pose.dim
    grainContext.drawLayer { layer in
      layer.clip(to: scene.body)
      let step = CGFloat(OrbGrain.tile) * 0.75
      var y: CGFloat = 0
      while y < scene.size.height {
        var x: CGFloat = 0
        while x < scene.size.width {
          layer.draw(tile, in: CGRect(x: x, y: y, width: step, height: step))
          x += step
        }
        y += step
      }
      layer.blendMode = .destinationIn
      layer.fill(
        scene.body,
        with: .radialGradient(
          Self.gradient(OrbLayers.grainFade) { .white.opacity($0) },
          center: scene.center, startRadius: 0, endRadius: scene.base * OrbLayers.grain.end))
    }
  }

  private func coreCenter(_ scene: Scene) -> CGPoint {
    CGPoint(
      x: scene.center.x - scene.base * OrbLayers.core.x,
      y: scene.center.y - scene.base * OrbLayers.core.y)
  }

  private static func gradient(
    _ stops: [(location: Double, alpha: Double)], _ color: (Double) -> Color
  ) -> Gradient {
    Gradient(stops: stops.map { .init(color: color($0.alpha), location: $0.location) })
  }
}
