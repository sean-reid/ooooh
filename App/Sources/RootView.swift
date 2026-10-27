import Billing
import Design
import NotesUI
import Persistence
import Settings
import SwiftUI

struct RootView: View {
  private let host = SessionHost.shared
  @AppStorage("onboardingComplete") private var onboardingComplete = false
  /// Unset completion shows the flow; `-onboarding 1` shows it again on a phone that finished it.
  @State private var showsOnboarding =
    !UserDefaults.standard.bool(forKey: "onboardingComplete")
    || UserDefaults.standard.bool(forKey: "onboarding")
  @State private var threads: [OpenThread] = []
  @State private var hidesThreads = false
  @State private var showsHistory = false
  @State private var showsSettings = false
  @State private var showsPaywall = false
  @Environment(\.dynamicTypeSize) private var typeSize
  #if DEBUG
    @State private var isRecordingFixture = false
  #endif

  private let store = AppStore.shared
  private var billing: BillingStore { AppBilling.store }
  private let launch: LaunchWork

  init(launch: LaunchWork = .shared) {
    self.launch = launch
  }

  private var controller: SessionController { host.controller }

  var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      if showsOnboarding {
        OnboardingFlow(start: requestCapture, done: finishOnboarding)
          .transition(.opacity)
      } else {
        switch controller.stage {
        case .idle, .failed:
          if typeSize.isAccessibilitySize {
            GeometryReader { proxy in
              ScrollView { home.frame(minHeight: proxy.size.height) }
            }
          } else {
            home
          }
        case .starting, .downloading, .running:
          SessionView(controller: controller)
        case .ended:
          ended
        }
      }
    }
    .animation(.easeInOut(duration: 0.4), value: controller.stage)
    .animation(.easeInOut(duration: 0.4), value: controller.notes)
    .animation(.easeInOut(duration: 0.4), value: showsOnboarding)
    .task {
      launch.run()
      ExportFile.removeExports()
      #if DEBUG
        if let store { await DebugHistory.apply(to: store) }
      #endif
      await loadThreads()
      try? await billing.load()
      #if DEBUG
        if UserDefaults.standard.bool(forKey: "demo") {
          showsOnboarding = false
          startDemo()
        }
      #endif
    }
    .sheet(isPresented: $showsHistory) {
      if let store { HistoryView(store: store).skySheet() }
    }
    .sheet(isPresented: $showsSettings) {
      if let store { SettingsSheet(store: store, billing: billing) }
    }
    .onChange(of: showsHistory) { _, shown in
      if !shown { Task { await loadThreads() } }
    }
    .onChange(of: showsSettings) { _, shown in
      if !shown { Task { await loadThreads() } }
    }
    .onChange(of: controller.stage) { _, stage in
      if stage == .ended { Task { await offerPaywall() } }
    }
    .sheet(isPresented: $showsPaywall) {
      PaywallView(store: billing) { showsPaywall = false }.skySheet()
    }
    #if DEBUG
      .sheet(isPresented: $isRecordingFixture) { RecordView().skySheet() }
    #endif
  }

  @ViewBuilder private var ended: some View {
    let transcript = controller.result?.transcript ?? []
    switch controller.notes {
    case .written(let notes):
      NotesView(notes: notes, transcript: transcript, date: controller.startedAt ?? .now) {
        reset()
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("notes.view")
    case .unavailable:
      PendingNotesView(
        state: controller.result?.state ?? .empty, transcript: transcript,
        line: PendingNotesView.line(for: controller)
      ) {
        reset()
      }
    case .empty:
      EmptySessionView { reset() }
    case .writing, nil:
      NotesWritingView()
    }
  }

  /// The orb gives way to the controls as type grows, instead of sitting under them.
  private var home: some View {
    VStack(spacing: 16) {
      HStack(spacing: 0) {
        Spacer()
        if store != nil {
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
      if case .failed(let failure) = controller.stage {
        Text(failure.message)
          .font(Typography.caption)
          .foregroundStyle(Palette.accent)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
      }
      startButton
      if !threads.isEmpty, !hidesThreads {
        CarryoverCard(threads: threads) { thread in
          Task { await controller.start(.microphone, carrying: thread) }
        } dismiss: {
          hidesThreads = true
        }
      }
      #if DEBUG
        if UserDefaults.standard.bool(forKey: "hide-debug") {
          Spacer().frame(height: 24)
        } else {
          HStack(spacing: 24) {
            Button {
              startDemo()
            } label: {
              Text("Demo").tapTarget()
            }
            .font(.footnote)
            .foregroundStyle(Palette.inkDim)
            .accessibilityIdentifier("home.demo")
            Button {
              isRecordingFixture = true
            } label: {
              Text("Record a fixture").tapTarget()
            }
            .font(.footnote)
            .foregroundStyle(Palette.inkDim)
            OrbGalleryButton()
          }
          .padding(.bottom, 8)
        }
      #else
        Spacer().frame(height: 24)
      #endif
    }
  }

  private var startButton: some View {
    Button("Start") {
      Task { await controller.start(.microphone) }
    }
    .buttonStyle(.amber)
    .padding(.horizontal, 32)
    .accessibilityLabel("Start a session")
    .accessibilityIdentifier("home.start")
  }

  private var historyButton: some View {
    iconButton("clock.arrow.circlepath", label: "History", id: "home.history") {
      showsHistory = true
    }
  }

  private var settingsButton: some View {
    iconButton("gearshape", label: "Settings", id: "home.settings") { showsSettings = true }
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

  /// A new controller for the next session, and the threads the one that just ended left open.
  private func reset() {
    host.reset()
    Task { await loadThreads() }
  }

  private func requestCapture() async -> CaptureDenial? {
    do {
      try await CapturePermissions.request()
      return nil
    } catch {
      return error.denial
    }
  }

  private func finishOnboarding() {
    onboardingComplete = true
    showsOnboarding = false
    Task { await controller.start(.microphone) }
  }

  private func offerPaywall() async {
    await billing.refresh()
    if Self.offersPaywall(billing) { showsPaywall = true }
  }

  /// True after a session ends with no free sessions left on a device that has not paid, or that
  /// paid in StoreKit's eyes while the Worker refused its transaction.
  static func offersPaywall(_ billing: BillingStore) -> Bool {
    let refusedWhilePaid = billing.freeSessionsRemaining == 0 && billing.isUnconfirmed
    return billing.entitlement == .free(remainingSessions: 0) || refusedWhilePaid
  }

  private func loadThreads() async {
    guard let store else { return }
    threads = (try? await store.openThreads(limit: 3)) ?? []
  }

  #if DEBUG
    /// Replays the bundled decision fixture through the whole pipeline at the `-demo-speed` pace.
    /// Also runs on launch with `-demo 1`.
    private func startDemo() {
      guard let url = try? DebugHistory.demoFixtureURL() else { return }
      Task { await controller.start(.fixture(url, speed: DemoSpeed.read())) }
    }
  #endif
}

#Preview {
  RootView()
}
