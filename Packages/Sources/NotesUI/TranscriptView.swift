import Design
import Notes
import SwiftUI
import Transcription

/// The words of a session, folded behind a row that says how long they run. Each utterance is a
/// paragraph that opens with its m:ss stamp; a line the app said sits in place in the dim ink
/// behind a mark, and a long press on it toggles the bad mark. Draws nothing for an empty
/// transcript.
public struct TranscriptView: View {
  public var transcript: [Segment]
  public var lines: [SpokenLine]
  /// Hears every toggle, with the mark the line now carries.
  public var onMarkBad: (SpokenLine, Bool) -> Void
  @State private var expanded: Bool
  @State private var marked: Set<UUID>
  @ScaledMetric(relativeTo: .body) private var lineSpacing = 6.0
  @ScaledMetric(relativeTo: .caption) private var markIndent = 36.0

  public init(
    transcript: [Segment], lines: [SpokenLine] = [], expanded: Bool = false,
    onMarkBad: @escaping (SpokenLine, Bool) -> Void = { _, _ in }
  ) {
    self.transcript = transcript
    self.lines = lines
    self.onMarkBad = onMarkBad
    _expanded = State(initialValue: expanded)
    _marked = State(initialValue: Set(lines.filter(\.bad).map(\.id)))
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
            ForEach(Array(transcript.interleaved(with: lines).enumerated()), id: \.offset) {
              _, entry in
              switch entry {
              case .said(let segment): paragraph(segment)
              case .asked(let line): asked(line)
              }
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

  private func asked(_ line: SpokenLine) -> some View {
    let bad = marked.contains(line.id)
    return VStack(alignment: .leading, spacing: 4) {
      (Text(line.stamp)
        .font(Typography.caption.monospacedDigit())
        + Text("  ")
        + Text(Image(systemName: "arrow.turn.down.right"))
        .font(Typography.caption)
        + Text(" ")
        + Text(line.text)
        .font(Typography.body)
        .strikethrough(bad))
        .foregroundStyle(Palette.inkDim)
        .lineSpacing(lineSpacing)
        .multilineTextAlignment(.leading)
      if bad {
        Text("Marked bad")
          .font(Typography.caption)
          .foregroundStyle(Palette.accent)
          .padding(.leading, markIndent)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .contentShape(Rectangle())
    .onLongPressGesture { toggle(line) }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(line.stamp), asked, \(line.text)" + (bad ? ", marked bad" : ""))
    .accessibilityHint("Long press to \(bad ? "clear" : "set") the bad mark")
    .accessibilityAction(named: bad ? "Clear bad mark" : "Mark bad") { toggle(line) }
    .accessibilityIdentifier("transcript.line.\(line.id.uuidString)")
  }

  private func toggle(_ line: SpokenLine) {
    let bad = !marked.contains(line.id)
    if bad {
      marked.insert(line.id)
    } else {
      marked.remove(line.id)
    }
    onMarkBad(line, bad)
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
