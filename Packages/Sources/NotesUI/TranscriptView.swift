import Design
import Notes
import SwiftUI
import Transcription

/// The words of a session, folded behind a row that says how long they run. Each utterance is a
/// paragraph that opens with its m:ss stamp. Draws nothing for an empty transcript.
public struct TranscriptView: View {
  public var transcript: [Segment]
  @State private var expanded: Bool
  @ScaledMetric(relativeTo: .body) private var lineSpacing = 6.0

  public init(transcript: [Segment], expanded: Bool = false) {
    self.transcript = transcript
    _expanded = State(initialValue: expanded)
  }

  public var body: some View {
    if !transcript.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text("Transcript")
          .font(Typography.title)
          .foregroundStyle(Palette.ink)
          .padding(.bottom, 8)
          .accessibilityAddTraits(.isHeader)
        row
        if expanded {
          VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(transcript.enumerated()), id: \.offset) { _, segment in
              paragraph(segment)
            }
          }
          .padding(.top, 12)
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("transcript.view")
    }
  }

  private var row: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
    } label: {
      HStack(spacing: 12) {
        Text(length)
          .font(Typography.body)
          .foregroundStyle(Palette.ink)
          .multilineTextAlignment(.leading)
        Spacer()
        Image(systemName: expanded ? "chevron.up" : "chevron.down")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(Palette.inkDim)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("transcript.toggle")
    .accessibilityValue(expanded ? "Expanded" : "Collapsed")
    .accessibilityHint(expanded ? "Hides the transcript" : "Shows the transcript")
  }

  private func paragraph(_ segment: Segment) -> some View {
    (Text(segment.stamp)
      .font(Typography.caption.monospacedDigit())
      .foregroundStyle(Palette.inkDim)
      + Text("  ")
      + Text(segment.text)
      .font(Typography.body)
      .foregroundStyle(Palette.ink))
      .lineSpacing(lineSpacing)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityLabel("\(segment.stamp), \(segment.text)")
  }

  /// Utterance count and the run time to the last word, in the shape the history row uses.
  var length: String {
    let count = transcript.count
    let utterances = count == 1 ? "1 utterance" : "\(count) utterances"
    let end = transcript.map(\.end).max() ?? 0
    let time = Duration.seconds(end).formatted(
      .units(allowed: [.minutes, .seconds], width: .narrow))
    return "\(utterances), \(time)"
  }
}
