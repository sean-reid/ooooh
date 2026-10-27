import Design
import Notes
import SwiftUI
import Transcription

struct NoteItemRow: View {
  var item: NoteItem
  var transcript: [Segment]
  var revealed: Bool
  var toggle: () -> Void
  @ScaledMetric(relativeTo: .body) private var dot = 8.0
  @ScaledMetric(relativeTo: .body) private var dotLift = 4.5

  var body: some View {
    if let span = item.span {
      Button(action: toggle) {
        VStack(alignment: .leading, spacing: 6) {
          line
          if revealed {
            Text(span.text(in: transcript))
              .font(Typography.body)
              .foregroundStyle(Palette.inkDim)
              .padding(.leading, 18)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(label)
      .accessibilityHint(revealed ? "Hides the words it came from" : "Shows the words it came from")
    } else {
      line
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
  }

  private var line: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Circle()
        .fill(item.resolved ? Palette.amberDim : Palette.accent)
        .frame(width: dot, height: dot)
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + dotLift }
      Text(item.text)
        .font(Typography.body)
        .strikethrough(item.resolved)
        .foregroundStyle(item.resolved ? Palette.inkDim : Palette.ink)
        .multilineTextAlignment(.leading)
    }
    .padding(.vertical, 6)
  }

  private var label: String {
    item.resolved ? "\(item.text), resolved" : item.text
  }
}
