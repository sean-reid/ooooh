import SwiftUI

/// The listener. Breathes with `level`, settles on silence, changes shape before it speaks.
public struct Orb: View {
  public var level: Double
  public var phase: OrbPhase
  public var time: TimeInterval?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @State private var motion: OrbMotion
  @State private var rests = false

  /// A fixed `time` renders one still frame; nil animates.
  public init(level: Double, phase: OrbPhase, time: TimeInterval? = nil) {
    self.init(level: level, phase: phase, time: time, motion: OrbMotion())
  }

  init(level: Double, phase: OrbPhase, time: TimeInterval? = nil, motion: OrbMotion) {
    self.level = level
    self.phase = phase
    self.time = time
    _motion = State(initialValue: motion)
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
        TimelineView(
          .animation(minimumInterval: 1 / 30, paused: Self.pauses(rests, level, phase))
        ) { context in
          canvas(motion.advance(to: context.date, level: level, phase: phase))
            .onChange(of: motion.rests, initial: true) { _, value in rests = value }
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(phase.accessibilityLabel)
    .accessibilityAddTraits(.isImage)
  }

  /// A paused timeline stops evaluating its content, so the inputs that would wake the orb are
  /// read here: the pause holds only while the frame rests and nothing has changed.
  static func pauses(_ rests: Bool, _ level: Double, _ phase: OrbPhase) -> Bool {
    rests && phase == .resting && level <= 0
  }

  private var stillOpacity: Double {
    switch phase {
    case .offline: 0.35
    case .aboutToSpeak: 1
    default: 0.6 + 0.35 * min(max(level, 0), 1)
    }
  }

  /// A canvas clips, so it is widened by this fraction of the side to carry the blurred halo past the frame.
  static let overflow: CGFloat = 0.25

  private func canvas(_ frame: OrbFrame) -> some View {
    let tint = OrbTint(colorScheme)
    return GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      let margin = (side * Self.overflow).rounded()
      Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) {
        context, _ in
        let grain = OrbGrain.image.map { context.resolve(Image(decorative: $0, scale: 1)) }
        context.translateBy(x: margin, y: margin)
        OrbPainter(frame: frame, tint: tint).paint(
          in: &context, size: CGSize(width: side, height: side), grain: grain)
      }
      .frame(width: side + 2 * margin, height: side + 2 * margin)
      .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    }
  }
}
