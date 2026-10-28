import Billing
import Design
import Notes
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
  #if DEBUG
    @State private var isRecordingFixture = false
  #endif

  private var store: SessionStore? { AppStore.shared.current }
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
          home
        case .starting, .downloading, .running:
          SessionView(controller: controller)
        case .ended:
          EndedView(controller: controller, onMarkBad: markLine, onDone: reset)
        }
      }
    }
    .animation(.easeInOut(duration: 0.4), value: controller.stage)
    .animation(.easeInOut(duration: 0.4), value: controller.notes)
    .animation(.easeInOut(duration: 0.4), value: showsOnboarding)
    .task {
      launch.run()
      ExportFile.removeExports()
      await applyDebugHistory()
      await loadThreads()
      try? await billing.load()
      startDemoIfAsked()
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

  private var home: some View {
    HomeView(
      threads: hidesThreads ? [] : threads, failure: startFailure, hasStore: store != nil,
      start: { Task { await controller.start(.microphone) } },
      carry: { thread in Task { await controller.start(.microphone, carrying: thread) } },
      dismissThreads: { hidesThreads = true },
      showHistory: { showsHistory = true },
      showSettings: { showsSettings = true },
      footer: {
        #if DEBUG
          DebugHomeRow(demo: startDemo, isRecordingFixture: $isRecordingFixture)
        #else
          Spacer().frame(height: 24)
        #endif
      })
  }

  private var startFailure: StartFailure? {
    if case .failed(let failure) = controller.stage { failure } else { nil }
  }

  private func markLine(_ line: SpokenLine, bad: Bool) {
    controller.markLine(line.id, bad: bad)
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
    /// `-reset-store 1` and `-seed-history 1`, applied before the threads load.
    private func applyDebugHistory() async {
      if let store { await DebugHistory.apply(to: store) }
    }

    /// `-demo 1` runs the demo on launch, past onboarding.
    private func startDemoIfAsked() {
      guard UserDefaults.standard.bool(forKey: "demo") else { return }
      showsOnboarding = false
      startDemo()
    }

    /// Replays the demo fixture through the whole pipeline at the `-demo-speed` pace.
    /// Also runs on launch with `-demo 1`.
    private func startDemo() {
      guard let url = DemoFixture.url() else { return }
      Task { await controller.start(.fixture(url, speed: DemoSpeed.read())) }
    }
  #else
    private func applyDebugHistory() async {}
    private func startDemoIfAsked() {}
  #endif
}

#Preview {
  RootView()
}
