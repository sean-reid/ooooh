import Design
import Persistence
import SwiftUI

/// The home screen: the orb, Start, the reason the last start failed, and the card of threads
/// left open. The orb gives way to the controls as type grows, instead of sitting under them.
struct HomeView<Footer: View>: View {
  let threads: [OpenThread]
  let failure: StartFailure?
  let hasStore: Bool
  let start: () -> Void
  let carry: (OpenThread) -> Void
  let dismissThreads: () -> Void
  let showHistory: () -> Void
  let showSettings: () -> Void
  let footer: Footer
  @Environment(\.dynamicTypeSize) private var typeSize

  init(
    threads: [OpenThread], failure: StartFailure?, hasStore: Bool,
    start: @escaping () -> Void, carry: @escaping (OpenThread) -> Void,
    dismissThreads: @escaping () -> Void, showHistory: @escaping () -> Void,
    showSettings: @escaping () -> Void, @ViewBuilder footer: () -> Footer
  ) {
    self.threads = threads
    self.failure = failure
    self.hasStore = hasStore
    self.start = start
    self.carry = carry
    self.dismissThreads = dismissThreads
    self.showHistory = showHistory
    self.showSettings = showSettings
    self.footer = footer()
  }

  var body: some View {
    if typeSize.isAccessibilitySize {
      GeometryReader { proxy in
        ScrollView { home.frame(minHeight: proxy.size.height) }
      }
    } else {
      home
    }
  }

  private var home: some View {
    VStack(spacing: 16) {
      HStack(spacing: 0) {
        Spacer()
        if hasStore {
          settingsButton
          historyButton
        }
      }
      .padding(.trailing, 20)
      .padding(.top, 8)
      Spacer(minLength: 0)
      VStack(spacing: 8) {
        Orb(level: 0, phase: .resting)
          .aspectRatio(1, contentMode: .fit)
          .frame(maxWidth: 240)
        Text("ooooh")
          .font(Typography.display)
          .foregroundStyle(Palette.ink)
      }
      Spacer(minLength: 0)
      if let failure {
        Text(failure.message)
          .font(Typography.caption)
          .foregroundStyle(Palette.accent)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
      }
      startButton
      if !threads.isEmpty {
        CarryoverCard(threads: threads, pick: carry, dismiss: dismissThreads)
      }
      footer
    }
  }

  private var startButton: some View {
    Button("Start", action: start)
      .buttonStyle(.amber)
      .padding(.horizontal, 32)
      .accessibilityLabel("Start a session")
      .accessibilityIdentifier("home.start")
  }

  private var historyButton: some View {
    iconButton("clock.arrow.circlepath", label: "History", id: "home.history", action: showHistory)
  }

  private var settingsButton: some View {
    iconButton("gearshape", label: "Settings", id: "home.settings", action: showSettings)
  }

  private func iconButton(
    _ symbol: String, label: String, id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.body.weight(.medium))
        .foregroundStyle(Palette.inkDim)
        .tapTarget()
    }
    .accessibilityLabel(label)
    .accessibilityIdentifier(id)
  }
}
