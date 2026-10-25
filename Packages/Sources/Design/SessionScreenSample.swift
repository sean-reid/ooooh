import SwiftUI

/// The session screen as the design intends it: orb, elapsed time, the last prompt.
public struct SessionScreenSample: View {
  public var elapsed: String
  public var prompt: String
  public var phase: OrbPhase
  public var level: Double
  public var time: TimeInterval?

  public init(
    elapsed: String = "12:34", prompt: String = "What would make it feel worth the cost?",
    phase: OrbPhase = .listening, level: Double = 0.4, time: TimeInterval? = nil
  ) {
    self.elapsed = elapsed
    self.prompt = prompt
    self.phase = phase
    self.level = level
    self.time = time
  }

  public var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      VStack(spacing: 0) {
        Text(elapsed)
          .font(Typography.caption)
          .monospacedDigit()
          .foregroundStyle(Palette.inkDim)
          .padding(.top, 20)
          .accessibilityLabel("Elapsed \(elapsed)")
        Spacer(minLength: 12)
        Orb(level: level, phase: phase, time: time)
          .frame(maxWidth: 320)
          .padding(.horizontal, 28)
        Spacer(minLength: 12)
        Text(prompt)
          .font(Typography.prompt)
          .foregroundStyle(Palette.ink)
          .multilineTextAlignment(.center)
          .layoutPriority(1)
          .padding(.horizontal, 32)
          .padding(.bottom, 56)
      }
    }
  }
}
