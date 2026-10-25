import Design
import SwiftUI

struct RootView: View {
  @State private var controller = SessionController()
  #if DEBUG
    @State private var isRecordingFixture = false
  #endif

  var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      switch controller.stage {
      case .idle, .failed:
        home
      case .starting, .running:
        SessionView(controller: controller)
      case .ended:
        NotesPlaceholderView(
          state: controller.result?.state ?? .empty,
          transcript: controller.result?.transcript ?? []
        ) {
          controller = SessionController()
        }
      }
    }
    .animation(.easeInOut(duration: 0.4), value: controller.stage)
    #if DEBUG
      .task {
        if UserDefaults.standard.bool(forKey: "demo") { startDemo() }
      }
      .sheet(isPresented: $isRecordingFixture) {
        RecordView()
        .presentationBackground(Palette.sky)
        .presentationDragIndicator(.visible)
      }
    #endif
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
