import Design
import Notes
import SwiftUI

/// An item in edit mode: delete on the left, the text as a tap-to-edit field, and on an open
/// thread the resolved mark on the right.
struct EditableNoteRow: View {
  var section: NoteSection
  var item: NoteItem
  @Binding var text: String
  var commit: () -> Void
  var delete: () -> Void
  var resolve: (Bool) -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Button(action: delete) {
        Image(systemName: "minus.circle.fill")
          .font(.body)
          .foregroundStyle(Palette.accent)
          .tapTarget()
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Delete")
      .accessibilityHint(item.text)
      NoteField(
        text: $text, placeholder: "", label: section.title, struck: item.resolved,
        staysOpen: false, commit: commit)
      if section == .openThreads {
        Button {
          resolve(!item.resolved)
        } label: {
          Image(systemName: item.resolved ? "checkmark.circle.fill" : "circle")
            .font(.body)
            .foregroundStyle(item.resolved ? Palette.accent : Palette.inkDim)
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Resolved")
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(item.resolved ? "On" : "Off")
      }
    }
  }
}

/// The last row of a section in edit mode. Return or the plus adds what was typed, and the
/// field stays open for the next one.
struct AddNoteRow: View {
  var section: NoteSection
  @Binding var text: String
  var commit: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Button(action: commit) {
        Image(systemName: "plus.circle")
          .font(.body)
          .foregroundStyle(Palette.accent)
          .tapTarget()
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Add to \(section.title.lowercased())")
      NoteField(
        text: $text, placeholder: "Add to \(section.title.lowercased())",
        label: "New item for \(section.title.lowercased())", struck: false, staysOpen: true,
        commit: commit)
    }
  }
}

/// Text over a hairline until tapped, then a wrapping field with the keyboard up. The field
/// commits on return and when it loses focus. ImageRenderer cannot draw a TextField, so the
/// resting state is what the snapshots show.
private struct NoteField: View {
  @Binding var text: String
  var placeholder: String
  var label: String
  var struck: Bool
  var staysOpen: Bool
  var commit: () -> Void
  @State private var active = false
  @FocusState private var focused: Bool

  var body: some View {
    Group {
      if active {
        TextField(placeholder, text: $text, axis: .vertical)
          .foregroundStyle(Palette.ink)
          .focused($focused)
          .submitLabel(.done)
          .onSubmit {
            commit()
            if !staysOpen { focused = false }
          }
          .onChange(of: focused) { _, now in
            if !now {
              commit()
              active = false
            }
          }
          .task { focused = true }
          .accessibilityLabel(label)
          .accessibilityIdentifier("notes.field")
      } else {
        Button {
          active = true
        } label: {
          Text(text.isEmpty ? placeholder : text)
            .strikethrough(struck)
            .foregroundStyle(text.isEmpty || struck ? Palette.inkDim : Palette.ink)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text.isEmpty ? placeholder : text)
        .accessibilityHint(text.isEmpty ? "Opens a field for a new item" : "Opens the text to edit")
      }
    }
    .font(Typography.body)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Palette.inkDim.opacity(0.3)).frame(height: 1)
    }
  }
}
