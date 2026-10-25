import Design
import SwiftUI
import Transcription

/// The notes screen shown when a session ends. Tapping an item shows the words it came from.
public struct NotesView: View {
  public var notes: SessionNotes
  public var transcript: [Segment]
  public var date: Date
  public var onDone: () -> Void
  /// ImageRenderer draws a ScrollView empty, so snapshots render the content unscrolled.
  var scrolls = true
  @State private var revealed: Set<String>

  public init(
    notes: SessionNotes, transcript: [Segment], date: Date = .now, revealed: Set<String> = [],
    onDone: @escaping () -> Void
  ) {
    self.notes = notes
    self.transcript = transcript
    self.date = date
    self.onDone = onDone
    _revealed = State(initialValue: revealed)
  }

  public var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      VStack(spacing: 0) {
        bar
        if scrolls {
          ScrollView { content }
        } else {
          GeometryReader { _ in content.fixedSize(horizontal: false, vertical: true) }.clipped()
        }
      }
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 32) {
      Text(notes.title)
        .font(Typography.display)
        .foregroundStyle(Palette.ink)
        .accessibilityAddTraits(.isHeader)
      if let summary = notes.summary {
        Text(summary)
          .font(Typography.body)
          .foregroundStyle(Palette.ink)
      }
      ForEach(notes.sections, id: \.name) { section in
        VStack(alignment: .leading, spacing: 4) {
          Text(section.name)
            .font(Typography.title)
            .foregroundStyle(Palette.ink)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
          ForEach(section.items) { item in
            NoteItemRow(item: item, transcript: transcript, revealed: revealed.contains(item.id)) {
              if revealed.contains(item.id) {
                revealed.remove(item.id)
              } else {
                revealed.insert(item.id)
              }
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 24)
    .padding(.bottom, 48)
  }

  private var bar: some View {
    HStack {
      ShareLink(item: notes.markdown(date: date)) {
        Image(systemName: "square.and.arrow.up")
          .font(.body.weight(.medium))
          .frame(minWidth: 44, minHeight: 44)
      }
      .accessibilityLabel("Share notes")
      Spacer()
      Button("Done", action: onDone)
        .font(.body.weight(.semibold))
        .frame(minWidth: 44, minHeight: 44)
    }
    .foregroundStyle(Palette.amber)
    .padding(.horizontal, 12)
    .padding(.top, 4)
  }
}

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
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
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
        .fill(item.resolved ? Palette.amberDim : Palette.amber)
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

extension TranscriptSpan {
  /// The words of every segment that overlaps the span, in order.
  public func text(in transcript: [Segment]) -> String {
    transcript
      .filter { $0.end >= start && $0.start <= end }
      .map(\.text)
      .joined(separator: " ")
  }
}
