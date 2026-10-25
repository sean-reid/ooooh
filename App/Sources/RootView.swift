import Design
import SwiftUI

struct RootView: View {
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
    }
  }
}

#Preview {
  RootView()
}
