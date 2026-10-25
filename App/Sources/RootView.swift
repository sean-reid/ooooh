import Design
import SwiftUI

struct RootView: View {
  #if DEBUG
    @State private var isRecordingFixture = false
  #endif

  var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      VStack(spacing: 8) {
        Orb(level: 0, phase: .resting)
          .frame(width: 240, height: 240)
        Text("ooooh")
          .font(Typography.display)
          .foregroundStyle(Palette.ink)
      }
      #if DEBUG
        VStack {
          Spacer()
          HStack(spacing: 24) {
            Button("Record a fixture") { isRecordingFixture = true }
              .font(.footnote)
              .foregroundStyle(Palette.inkDim)
              .frame(minHeight: 44)
            OrbGalleryButton()
          }
          .padding(.bottom, 8)
        }
      #endif
    }
    #if DEBUG
      .sheet(isPresented: $isRecordingFixture) {
        RecordView()
        .presentationBackground(Palette.sky)
        .presentationDragIndicator(.visible)
      }
    #endif
  }
}

#Preview {
  RootView()
}
