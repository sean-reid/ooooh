import Billing
import Design
import Notes
import Persistence
import SwiftUI

struct RootView: View {
  @State private var controller = SessionController(environment: .app)
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
  private let billing = AppBilling.store

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
        case .starting, .running:
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
    .onChange(of: controller.admission) { _, admission in
      if let admission { AppBilling.freeSessions.record(admission) }
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
      PendingNotesView(state: controller.result?.state ?? .empty, transcript: transcript) {
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
      if case .failed(let message) = controller.stage {
        Text(message)
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
        HStack(spacing: 24) {
          Button("Demo") { startDemo() }
            .font(.footnote)
            .foregroundStyle(Palette.inkDim)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier("home.demo")
          Button("Record a fixture") { isRecordingFixture = true }
            .font(.footnote)
            .foregroundStyle(Palette.inkDim)
            .frame(minHeight: 44)
          OrbGalleryButton()
        }
        .padding(.bottom, 8)
      #else
        Spacer().frame(height: 24)
      #endif
    }
  }

  private var startButton: some View {
    Button {
      Task { await controller.start(.microphone) }
    } label: {
      Text("Start")
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 56)
    }
    .buttonStyle(.plain)
    .foregroundStyle(Palette.inkOnAmber)
    .background(Palette.amber, in: Capsule())
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
        .frame(minWidth: 44, minHeight: 44)
    }
    .accessibilityLabel(label)
    .accessibilityIdentifier(id)
  }

  /// A new controller for the next session, and the threads the one that just ended left open.
  private func reset() {
    controller = SessionController(environment: .app)
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

  /// After a session ends with no free sessions left on a device that has not paid.
  private func offerPaywall() async {
    await billing.refresh()
    if billing.entitlement == .free(remainingSessions: 0) { showsPaywall = true }
  }

  private func loadThreads() async {
    guard let store else { return }
    threads = (try? await store.openThreads(limit: 3)) ?? []
  }

  #if DEBUG
    /// Replays the bundled decision fixture through the whole pipeline at 1x. Also runs on launch with `-demo 1`.
    private func startDemo() {
      guard let url = Bundle.main.url(forResource: "decision.fixture", withExtension: "json")
      else { return }
      Task { await controller.start(.fixture(url, speed: 1)) }
    }
  #endif
}

#Preview {
  RootView()
}
