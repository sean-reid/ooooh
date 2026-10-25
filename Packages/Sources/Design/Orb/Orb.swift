import SwiftUI

/// The listener. Breathes with `level`, settles on silence, changes shape before it speaks.
public struct Orb: View {
  public var level: Double
  public var phase: OrbPhase
  public var time: TimeInterval?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @State private var motion = OrbMotion()

  /// A fixed `time` renders one still frame; nil animates.
  public init(level: Double, phase: OrbPhase, time: TimeInterval? = nil) {
    self.level = level
    self.phase = phase
    self.time = time
  }

  public var body: some View {
    Group {
      if reduceMotion {
        canvas(OrbFrame(clock: 0, breath: 0.3, pose: .still))
          .opacity(stillOpacity)
          .animation(.easeInOut(duration: 1.2), value: stillOpacity)
      } else if let time {
        canvas(OrbMotion.still(at: time, level: level, phase: phase))
      } else {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
          canvas(motion.advance(to: context.date, level: level, phase: phase))
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(phase.accessibilityLabel)
    .accessibilityAddTraits(.isImage)
  }

  private var stillOpacity: Double {
    switch phase {
    case .offline: 0.35
    case .aboutToSpeak: 1
    default: 0.6 + 0.35 * min(max(level, 0), 1)
    }
  }

  private func canvas(_ frame: OrbFrame) -> some View {
    let tint = OrbTint(colorScheme)
    return Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) {
      context, size in
      let grain = OrbGrain.image.map { context.resolve(Image(decorative: $0, scale: 1)) }
      OrbPainter(frame: frame, tint: tint).paint(in: &context, size: size, grain: grain)
    }
  }
}
