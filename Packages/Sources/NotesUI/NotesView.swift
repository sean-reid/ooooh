import Design
import Notes
import SwiftUI
import Transcription

/// The notes screen shown when a session ends. Tapping an item shows the words it came from.
/// With `editing` set, Edit turns every item into a field with a delete, gives each section an
/// add row, and puts a resolved mark on the open threads.
public struct NotesView: View {
  public var notes: SessionNotes
  public var transcript: [Segment]
  public var lines: [SpokenLine]
  public var date: Date
  public var editing: NoteEditing?
  /// One line under the bar, for an edit the store refused.
  public var notice: String?
  public var onDone: () -> Void
  /// Hears every bad-mark toggle on a line the app said.
  public var onMarkBad: (SpokenLine, Bool) -> Void
  /// ImageRenderer draws a ScrollView empty, so snapshots render the content unscrolled.
  var scrolls = true
  var transcriptExpanded = false
  @State private var revealed: Set<String>
  @State private var isEditing: Bool
  @State private var drafts: [NoteDraft: String] = [:]

  public init(
    notes: SessionNotes, transcript: [Segment], lines: [SpokenLine] = [], date: Date = .now,
    revealed: Set<String> = [], editing: NoteEditing? = nil, isEditing: Bool = false,
    notice: String? = nil, onMarkBad: @escaping (SpokenLine, Bool) -> Void = { _, _ in },
    onDone: @escaping () -> Void
  ) {
    self.notes = notes
    self.transcript = transcript
    self.lines = lines
    self.onMarkBad = onMarkBad
    self.date = date
    self.editing = editing
    self.notice = notice
    self.onDone = onDone
    _revealed = State(initialValue: revealed)
    _isEditing = State(initialValue: isEditing && editing != nil)
  }

  public var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      VStack(spacing: 0) {
        bar
        if let notice {
          Text(notice)
            .font(Typography.caption)
            .foregroundStyle(Palette.accent)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .accessibilityIdentifier("notes.notice")
        }
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
      ForEach(sections, id: \.section) { section in
        VStack(alignment: .leading, spacing: 4) {
          Text(section.section.title)
            .font(Typography.title)
            .foregroundStyle(Palette.ink)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
          ForEach(section.items) { item in
            if isEditing, let editing {
              EditableNoteRow(
                section: section.section, item: item,
                text: draft(.item(section.section, item.id), fallback: item.text),
                commit: { commit(.item(section.section, item.id)) },
                delete: { editing.delete(section.section, item) },
                resolve: { editing.resolve(item, $0) })
            } else {
              NoteItemRow(item: item, transcript: transcript, revealed: revealed.contains(item.id))
              {
                if revealed.contains(item.id) {
                  revealed.remove(item.id)
                } else {
                  revealed.insert(item.id)
                }
              }
            }
          }
          if isEditing {
            AddNoteRow(
              section: section.section, text: draft(.add(section.section), fallback: ""),
              commit: { commit(.add(section.section)) })
          }
        }
      }
      TranscriptView(
        transcript: transcript, lines: lines, expanded: transcriptExpanded, onMarkBad: onMarkBad)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 24)
    .padding(.bottom, 48)
  }

  /// Every section while editing, so an empty one can take an item; otherwise the filled ones.
  private var sections: [(section: NoteSection, items: [NoteItem])] {
    isEditing ? NoteSection.allCases.map { ($0, notes[$0]) } : notes.sections
  }

  private var bar: some View {
    HStack {
      ShareLink(item: notes.markdown(date: date)) {
        Image(systemName: "square.and.arrow.up")
          .font(.body.weight(.medium))
          .tapTarget()
      }
      .accessibilityLabel("Share notes")
      Spacer()
      if isEditing {
        Button(action: finishEditing) { Text("Done").tapTarget() }
          .accessibilityLabel("Done editing")
          .accessibilityIdentifier("notes.editing.done")
          .font(.body.weight(.semibold))
      } else {
        if editing != nil {
          Button {
            isEditing = true
          } label: {
            Text("Edit").tapTarget()
          }
          .accessibilityLabel("Edit notes")
          .accessibilityIdentifier("notes.edit")
          .font(.body.weight(.medium))
        }
        Button(action: onDone) { Text("Done").tapTarget() }
          .accessibilityIdentifier("notes.done")
          .font(.body.weight(.semibold))
      }
    }
    .foregroundStyle(Palette.accent)
    .padding(.horizontal, 12)
    .padding(.top, 4)
  }

  private func draft(_ key: NoteDraft, fallback: String) -> Binding<String> {
    Binding(get: { drafts[key] ?? fallback }, set: { drafts[key] = $0 })
  }

  /// Writes one field's text through the hooks. Blank text on an item reverts it.
  private func commit(_ key: NoteDraft) {
    guard let editing, let typed = drafts.removeValue(forKey: key) else { return }
    let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    switch key {
    case .item(let section, let id):
      guard let item = notes[section].first(where: { $0.id == id }), item.text != text else {
        return
      }
      editing.edit(section, item, text)
    case .add(let section):
      editing.add(section, text)
    }
  }

  private func finishEditing() {
    for key in drafts.keys { commit(key) }
    isEditing = false
  }
}
