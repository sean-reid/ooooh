import Notes
import NotesUI
import SwiftUI

/// The notes screen over an editor, so every edit lands in the store.
struct EditableNotesView: View {
  let editor: NotesEditor
  var lines: [SpokenLine] = []
  var onMarkBad: (SpokenLine, Bool) -> Void = { _, _ in }
  let onDone: () -> Void

  var body: some View {
    NotesView(
      notes: editor.notes, transcript: editor.transcript, lines: lines, date: editor.date,
      editing: editor.hooks, notice: editor.failure, onMarkBad: onMarkBad, onDone: onDone
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("notes.view")
  }
}
