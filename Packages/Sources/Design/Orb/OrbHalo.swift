import SwiftUI

/// The blurred halo at full glow, rendered once per tint and pixel size. Its gradient reaches zero
/// at the blob's mean radius, so the wobble and stretch only clip a fringe the blur erases, and one
/// disc scaled by breath and faded by glow stands in for every frame.
@MainActor
enum OrbHalo {
  /// Half-side of the image as a multiple of the body radius: the halo plus three blur radii.
  nonisolated static let extent = OrbLayers.halo.radius + 3 * OrbLayers.halo.blur
  /// One pixel per point: the blur spans tens of points, so upscaling it costs nothing visible.
  nonisolated static let scale: CGFloat = 1

  private struct Key: Hashable {
    var scheme: ColorScheme
    var points: Int
  }

  private static var cache: [Key: CGImage] = [:]

  /// The disc as the canvas draws it: bilinear is enough for a field this smooth, and the default
  /// quality costs the CPU path more than the blur it replaces.
  nonisolated static func image(_ disc: CGImage) -> Image {
    Image(decorative: disc, scale: scale).interpolation(.low)
  }

  /// The disc for an orb of `side` points, sized for the deepest breath so breath only shrinks it.
  static func image(for tint: OrbTint, side: CGFloat) -> CGImage? {
    let base = side * OrbLayers.body * (1 + OrbLayers.breathGrow)
    let key = Key(scheme: tint.scheme, points: Int(base.rounded()))
    if let image = cache[key] { return image }
    let half = base * extent
    let renderer = ImageRenderer(
      content: Canvas(opaque: false, colorMode: .nonLinear) { context, size in
        OrbPainter.blurredHalo(
          in: &context, center: CGPoint(x: size.width / 2, y: size.height / 2), base: base,
          tint: tint, pose: OrbPose(stretch: 1, glow: 1, drift: 0, dim: 0, speed: 0), clock: 0)
      }
      .frame(width: 2 * half, height: 2 * half))
    renderer.scale = scale
    let image = renderer.cgImage
    cache[key] = image
    return image
  }
}
