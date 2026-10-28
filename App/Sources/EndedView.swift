import Notes
import NotesUI
import SwiftUI

/// The screen after End: the notes once written, the compact state when there are none, the
/// empty session, or the wait for the notes.
struct EndedView: View {
  let controller: SessionController
  let onMarkBad: (SpokenLine, Bool) -> Void
  let onDone: () -> Void

  var body: some View {
    let transcript = controller.result?.transcript ?? []
    switch controller.notes {
    case .written(let notes):
      if let editor = controller.editor {
        EditableNotesView(
          editor: editor, lines: controller.lines, onMarkBad: onMarkBad, onDone: onDone)
      } else {
        NotesView(
          notes: notes, transcript: transcript, lines: controller.lines,
          date: controller.startedAt ?? .now, onMarkBad: onMarkBad, onDone: onDone
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notes.view")
      }
    case .unavailable:
      PendingNotesView(
        state: controller.result?.state ?? .empty, transcript: transcript,
        line: PendingNotesView.line(for: controller), lines: controller.lines,
        onMarkBad: onMarkBad, done: onDone)
    case .empty:
      EmptySessionView(done: onDone)
    case .writing, nil:
      NotesWritingView()
    }
  }
}
