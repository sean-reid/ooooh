#if DEBUG
  import Design
  import SwiftUI

  /// Demo, Record a fixture, and the orb gallery under Start. `-hide-debug 1` leaves the gap
  /// they take, so a store capture reads as the shipped screen.
  struct DebugHomeRow: View {
    let demo: () -> Void
    @Binding var isRecordingFixture: Bool

    var body: some View {
      if UserDefaults.standard.bool(forKey: "hide-debug") {
        Spacer().frame(height: 24)
      } else {
        HStack(spacing: 24) {
          Button(action: demo) {
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
    }
  }
#endif
