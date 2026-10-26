import Design
import Persistence
import SwiftUI

/// Up to three open threads from past sessions. Tapping one starts a session on it.
struct CarryoverCard: View {
  let threads: [OpenThread]
  let pick: (OpenThread) -> Void
  let dismiss: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .top) {
        Text("Still open from last time")
          .font(Typography.caption)
          .foregroundStyle(Palette.inkDim)
          .fixedSize(horizontal: false, vertical: true)
          .frame(minHeight: 44, alignment: .leading)
        Spacer()
        Button(action: dismiss) {
          Image(systemName: "xmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.inkDim)
            .tapTarget()
        }
        .accessibilityLabel("Dismiss the open threads")
        .accessibilityIdentifier("home.carryover.dismiss")
      }
      ForEach(threads) { thread in
        Button {
          pick(thread)
        } label: {
          Text(thread.text)
            .font(Typography.body)
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(.leading)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pick up \(thread.text)")
        .accessibilityHint("Starts a session on this thread")
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 12)
    .background(Palette.skyRaised, in: RoundedRectangle(cornerRadius: 20))
    .padding(.horizontal, 32)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("home.carryover")
  }
}
