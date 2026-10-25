import Design
import SwiftUI

struct RootView: View {
  #if DEBUG
    @State private var isRecordingFixture = false
  #endif

  var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      VStack(spacing: 24) {
        Circle()
          .fill(Palette.amber)
          .frame(width: 96, height: 96)
          .shadow(color: Palette.amberDim, radius: 40)
          .accessibilityLabel("Your listener, resting")
        Text("ooooh")
          .font(.system(size: 34, weight: .regular, design: .serif))
          .foregroundStyle(Palette.ink)
      }
      #if DEBUG
        VStack {
          Spacer()
          Button("Record a fixture") { isRecordingFixture = true }
            .font(.footnote)
            .foregroundStyle(Palette.inkDim)
            .frame(minHeight: 44)
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
