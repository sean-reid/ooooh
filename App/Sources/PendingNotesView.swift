import Design
import State
import SwiftUI
import Transcription

/// The session's compact state, shown when the notes could not be written yet.
struct PendingNotesView: View {
  let state: CompactState
  let transcript: [Segment]
  let done: () -> Void

  var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      VStack(alignment: .leading, spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 28) {
            Text("Notes")
              .font(Typography.title)
              .foregroundStyle(Palette.ink)
              .accessibilityAddTraits(.isHeader)
            Text("Your listener is offline. The notes will be written when it is back.")
              .font(Typography.body)
              .foregroundStyle(Palette.inkDim)
              .accessibilityIdentifier("notes.pending.line")
            Text("^[\(transcript.count) utterance](inflect: true), \(state.mode.rawValue)")
              .font(Typography.caption)
              .foregroundStyle(Palette.inkDim)
            section("Thread", lines: state.currentThread.isEmpty ? [] : [state.currentThread])
            section("Ideas", lines: state.mainIdeas.map(\.text))
            section("Decisions", lines: state.decisions.map(\.text))
            section("Open questions", lines: state.openQuestions.map(\.text))
            section("Uncertainties", lines: state.uncertainties.map(\.text))
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(24)
        }
        Button(action: done) {
          Text("Done")
            .font(Typography.body)
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.sky)
        .background(Palette.amber, in: Capsule())
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .accessibilityIdentifier("notes.done")
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("notes.pending")
    }
  }

  @ViewBuilder private func section(_ title: String, lines: [String]) -> some View {
    if !lines.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text(title)
          .font(Typography.caption)
          .foregroundStyle(Palette.inkDim)
          .accessibilityAddTraits(.isHeader)
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
          Text(line)
            .font(Typography.body)
            .foregroundStyle(Palette.ink)
        }
      }
    }
  }
}
