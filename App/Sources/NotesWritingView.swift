import Design
import SwiftUI

/// The wait between End and the notes: the orb settling and one line.
struct NotesWritingView: View {
  var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      VStack(spacing: 32) {
        Orb(level: 0, phase: .resting)
          .frame(maxWidth: 240)
          .padding(.horizontal, 28)
        Text("writing your notes")
          .font(Typography.prompt)
          .foregroundStyle(Palette.inkDim)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
          .accessibilityIdentifier("notes.writing")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Writing your notes")
  }
}
