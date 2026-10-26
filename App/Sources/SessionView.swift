import Design
import SwiftUI

/// The screen during a session: elapsed time, the orb, the last prompt, End.
struct SessionView: View {
  let controller: SessionController
  @ScaledMetric(relativeTo: .title2) private var promptMinHeight = 72

  var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      VStack(spacing: 0) {
        clock
        Spacer(minLength: 12)
        Orb(level: controller.level, phase: controller.phase)
          .frame(maxWidth: 320)
          .padding(.horizontal, 28)
        Spacer(minLength: 12)
        prompt
        statusLine
        endButton
      }
    }
  }

  private var clock: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let text = Self.clockText(controller.elapsed(at: context.date))
      Text(text)
        .font(Typography.caption)
        .monospacedDigit()
        .foregroundStyle(Palette.inkDim)
        .padding(.top, 20)
        .accessibilityLabel("Elapsed \(text)")
        .accessibilityIdentifier("session.elapsed")
    }
  }

  private var prompt: some View {
    Text(controller.lastPrompt ?? "")
      .font(Typography.prompt)
      .foregroundStyle(Palette.ink)
      .multilineTextAlignment(.center)
      .layoutPriority(1)
      .frame(maxWidth: .infinity, minHeight: promptMinHeight)
      .padding(.horizontal, 32)
      .accessibilityIdentifier("session.prompt")
      .accessibilityHidden(controller.lastPrompt == nil)
  }

  @ViewBuilder private var statusLine: some View {
    if let status = Self.status(for: controller) {
      Text(status.text)
        .font(Typography.caption)
        .foregroundStyle(Palette.inkDim)
        .multilineTextAlignment(.center)
        .padding(.top, 12)
        .padding(.horizontal, 32)
        .accessibilityIdentifier(status.id)
    }
  }

  /// One line under the prompt saying why nothing is asked. A refusal explains the silence on
  /// its own, so it wins over the clock, and the clock over offline.
  static func status(for controller: SessionController) -> (text: String, id: String)? {
    if controller.promptsRefused {
      return ("listening only, this month's free sessions are used up", "session.quota")
    }
    if controller.clockRefused {
      return (
        "listening only, your phone's clock is off, so your listener can't verify it",
        "session.clock"
      )
    }
    if controller.isOffline {
      return ("listening only, your listener is offline", "session.offline")
    }
    return nil
  }

  private var endButton: some View {
    Button {
      Task { await controller.end() }
    } label: {
      Text("End")
        .font(Typography.body)
        .frame(minWidth: 120, minHeight: 44)
    }
    .buttonStyle(.plain)
    .foregroundStyle(Palette.ink)
    .background(Palette.skyRaised, in: Capsule())
    .padding(.top, 20)
    .padding(.bottom, 12)
    .accessibilityLabel("End the session")
    .accessibilityIdentifier("session.end")
  }

  static func clockText(_ elapsed: TimeInterval) -> String {
    let seconds = Int(elapsed.rounded(.down))
    return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
  }
}
