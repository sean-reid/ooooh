import Design
import SwiftUI

/// Shown when a session ended before anything was heard.
struct EmptySessionView: View {
  let done: () -> Void

  var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      VStack(spacing: 0) {
        Spacer()
        Orb(level: 0, phase: .resting)
          .frame(maxWidth: 240)
          .padding(.horizontal, 28)
        Text("Nothing was said this time.")
          .font(Typography.prompt)
          .foregroundStyle(Palette.inkDim)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
          .padding(.top, 32)
          .accessibilityIdentifier("notes.empty")
        Spacer()
        Button("Done", action: done)
          .buttonStyle(.amber)
          .padding(.horizontal, 24)
          .padding(.bottom, 12)
          .accessibilityIdentifier("notes.done")
      }
    }
  }
}
