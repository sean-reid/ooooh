import Design
import Notes
import SwiftUI

struct RootView: View {
  @State private var controller = SessionController(environment: .app)
  @AppStorage("onboardingComplete") private var onboardingComplete = false
  /// Unset completion shows the flow; `-onboarding 1` shows it again on a phone that finished it.
  @State private var showsOnboarding =
    !UserDefaults.standard.bool(forKey: "onboardingComplete")
    || UserDefaults.standard.bool(forKey: "onboarding")
  #if DEBUG
    @State private var isRecordingFixture = false
  #endif

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
    #if DEBUG
      .task {
        if UserDefaults.standard.bool(forKey: "demo") {
          showsOnboarding = false
          startDemo()
        }
      }
      .sheet(isPresented: $isRecordingFixture) {
        RecordView()
        .presentationBackground(Palette.sky)
        .presentationDragIndicator(.visible)
      }
    #endif
  }

  @ViewBuilder private var ended: some View {
    let transcript = controller.result?.transcript ?? []
    switch controller.notes {
    case .written(let notes):
      NotesView(notes: notes, transcript: transcript, date: controller.startedAt ?? .now) {
        controller = SessionController(environment: .app)
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("notes.view")
    case .unavailable:
      PendingNotesView(state: controller.result?.state ?? .empty, transcript: transcript) {
        controller = SessionController(environment: .app)
      }
    case .writing, nil:
      NotesWritingView()
    }
  }

  private var home: some View {
    ZStack {
      VStack(spacing: 8) {
        Orb(level: 0, phase: .resting)
          .frame(width: 240, height: 240)
        Text("ooooh")
          .font(Typography.display)
          .foregroundStyle(Palette.ink)
      }
      VStack(spacing: 16) {
        Spacer()
        if case .failed(let message) = controller.stage {
          Text(message)
            .font(Typography.caption)
            .foregroundStyle(Palette.accent)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
        startButton
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
