import SwiftUI
import Testing

@testable import Design

/// Draws the orb at the session screen's 320 pt through a 2x CGContext, one layer at a time, and
/// prints the median milliseconds per frame. Nothing here is gated on wall clock. Suites in one
/// process share the cores, so the numbers mean something only when this suite runs alone.
@MainActor
@Suite struct OrbRenderBenchmark {
  static let side: CGFloat = 320
  static let scale: CGFloat = 2
  static let frames = 20
  static let repeats = 5

  @Test func printsMillisecondsPerFrameAndLayer() {
    let tint = OrbTint(.dark)
    let margin = (Self.side * Orb.overflow).rounded()
    let canvasSide = Self.side + 2 * margin
    let size = CGSize(width: Self.side, height: Self.side)
    let pose = OrbPose.target(for: .listening)
    let grain = OrbGrain.image.map { Image(decorative: $0, scale: 1) }
    let renderer = ImageRenderer(content: AnyView(Color.clear))
    renderer.scale = Self.scale

    func pass(_ paint: @escaping (inout GraphicsContext, OrbFrame) -> Void) -> Double {
      var total: Duration = .zero
      for index in 0..<Self.frames {
        let frame = OrbFrame(clock: 4.2 + Double(index) / 30, breath: 0.3, pose: pose)
        renderer.content = AnyView(
          Canvas(opaque: false, colorMode: .nonLinear) { context, _ in
            context.translateBy(x: margin, y: margin)
            paint(&context, frame)
          }
          .frame(width: canvasSide, height: canvasSide))
        Self.context.clear(CGRect(origin: .zero, size: Self.bitmap))
        let start = ContinuousClock.now
        renderer.render { _, draw in draw(Self.context) }
        total += ContinuousClock.now - start
      }
      return total / Self.frames / .milliseconds(1)
    }

    var variants: [(name: String, paint: (inout GraphicsContext, OrbFrame) -> Void)] = [
      ("empty", { _, _ in })
    ]
    for layer in OrbPainter.Layer.allCases {
      variants.append(
        (
          layer.rawValue,
          { context, frame in
            OrbPainter(frame: frame, tint: tint).paint(
              layer, in: &context, size: size, grain: grain.map { context.resolve($0) })
          }
        ))
    }
    variants.append(
      (
        "frame",
        { context, frame in
          OrbPainter(frame: frame, tint: tint).paint(
            in: &context, size: size, grain: grain.map { context.resolve($0) })
        }
      ))

    var samples = [[Double]](repeating: [], count: variants.count)
    for _ in 0..<Self.repeats {
      for (index, variant) in variants.enumerated() {
        samples[index].append(pass(variant.paint))
      }
    }
    let medians = samples.map { $0.sorted()[$0.count / 2] }
    let empty = medians[0]
    print(
      "orb render at \(Int(Self.side)) pt, \(Int(Self.scale))x, median of \(Self.repeats) passes "
        + "of \(Self.frames) frames, empty canvas \(String(format: "%.2f", empty)) ms subtracted")
    for (index, variant) in variants.enumerated().dropFirst() {
      let name = variant.name.padding(toLength: 6, withPad: " ", startingAt: 0)
      print("  \(name) \(String(format: "%6.2f", medians[index] - empty)) ms/frame")
    }
    #expect(medians.last! > empty)
  }

  private static let bitmap = CGSize(
    width: ((side + 2 * (side * Orb.overflow).rounded()) * scale).rounded(),
    height: ((side + 2 * (side * Orb.overflow).rounded()) * scale).rounded())

  /// One bitmap for every render so allocation stays out of the numbers.
  private static let context: CGContext = {
    CGContext(
      data: nil, width: Int(bitmap.width), height: Int(bitmap.height), bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  }()
}
