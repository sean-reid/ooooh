import NotesUI
import SwiftUI

/// The notes screen over an editor, so every edit lands in the store.
struct EditableNotesView: View {
  let editor: NotesEditor
  let onDone: () -> Void

  var body: some View {
    NotesView(
      notes: editor.notes, transcript: editor.transcript, date: editor.date,
      editing: editor.hooks, notice: editor.failure, onDone: onDone
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("notes.view")
  }
}
