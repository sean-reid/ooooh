import Design
import SwiftUI

/// The screen during a session: elapsed time, the orb, the last prompt, End. Paused, the line
/// under the prompt says so and offers Resume.
struct SessionView: View {
  let controller: SessionController
  /// A fixed time renders one still orb, as the snapshots do.
  var orbTime: TimeInterval?
  /// A fixed elapsed time renders one clock reading, as the snapshots do.
  var elapsed: TimeInterval?
  @ScaledMetric(relativeTo: .title2) private var promptMinHeight = 72

  var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      VStack(spacing: 0) {
        clock
        Spacer(minLength: 12)
        Orb(level: controller.level, phase: controller.phase, time: orbTime)
          .frame(maxWidth: 320)
          .padding(.horizontal, 28)
        Spacer(minLength: 12)
        if controller.stage == .downloading {
          download
        } else {
          prompt
          if controller.isPaused { pausedLine } else { statusLine }
        }
        endButton
      }
    }
  }

  private var download: some View {
    VStack(spacing: 14) {
      Text("Downloading the speech model")
        .font(Typography.caption)
        .foregroundStyle(Palette.inkDim)
        .accessibilityIdentifier("session.download")
      DownloadBar(fraction: controller.downloadProgress)
        .frame(maxWidth: 180)
        .accessibilityLabel("Speech model download")
        .accessibilityValue("\(Int((controller.downloadProgress * 100).rounded())) percent")
    }
    .frame(maxWidth: .infinity, minHeight: promptMinHeight)
    .padding(.horizontal, 32)
  }

  private var clock: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let text = Self.clockText(elapsed ?? controller.elapsed(at: context.date))
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

  private var pausedLine: some View {
    VStack(spacing: 8) {
      Text("paused")
        .font(Typography.caption)
        .foregroundStyle(Palette.inkDim)
        .accessibilityIdentifier("session.paused")
      Button {
        Task { await controller.resume() }
      } label: {
        Text("Resume")
          .font(Typography.body)
          .frame(minWidth: 120, minHeight: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(Palette.inkOnAmber)
      .background(Palette.amber, in: Capsule())
      .accessibilityLabel("Resume the session")
      .accessibilityIdentifier("session.resume")
    }
    .padding(.top, 12)
    .padding(.horizontal, 32)
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

/// A 3 pt track in the raised sky, filled in amber to `fraction`.
private struct DownloadBar: View {
  var fraction: Double

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(Palette.skyRaised)
        Capsule().fill(Palette.amber)
          .frame(width: proxy.size.width * min(max(fraction, 0), 1))
      }
    }
    .frame(height: 3)
    .animation(.linear(duration: 0.2), value: fraction)
  }
}
