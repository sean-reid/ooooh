#if canImport(UIKit)
  import SnapshotTesting
  import SwiftUI
  import TestSupport
  import Testing
  import UIKit

  import Notes

  @testable import NotesUI

  /// Reference PNGs live in __Snapshots__ and are rendered on the iPhone 17 Pro simulator.
  @MainActor
  @Suite struct NotesSnapshotTests {
    typealias Sample = (name: String, notes: SessionNotes, revealed: Set<String>)

    nonisolated static let samples: [Sample] = [
      ("full", NotesSample.full, ["money-versus-time"]),
      ("short", NotesSample.short, []),
    ]

    @Test(arguments: samples, [ColorScheme.dark, .light])
    func notes(
      sample: (name: String, notes: SessionNotes, revealed: Set<String>), scheme: ColorScheme
    ) {
      let image = render(view(sample.notes, revealed: sample.revealed), scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "\(sample.name)-402-\(scheme.name)")
    }

    @Test(arguments: samples)
    func notesAccessibility3(sample: Sample) {
      let image = render(
        view(sample.notes, revealed: sample.revealed), scheme: .dark, type: .accessibility3)
      assertSnapshot(of: image, as: .pixels, named: "\(sample.name)-402-accessibility3-dark")
    }

    /// The Edit control in the bar, the items still read-only.
    @Test(arguments: [ColorScheme.dark, .light])
    func editable(scheme: ColorScheme) {
      let image = render(view(NotesSample.full, revealed: [], editable: true), scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "full-402-\(scheme.name)")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func editing(scheme: ColorScheme) {
      let image = render(
        view(NotesSample.full, revealed: [], editable: true, isEditing: true), scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "full-402-\(scheme.name)")
    }

    @Test func editingAccessibility3() {
      let image = render(
        view(NotesSample.full, revealed: [], editable: true, isEditing: true), scheme: .dark,
        type: .accessibility3)
      assertSnapshot(of: image, as: .pixels, named: "full-402-accessibility3-dark")
    }

    /// The transcript open under the notes, with two lines the app said, one marked bad.
    @Test(arguments: [ColorScheme.dark, .light])
    func withLines(scheme: ColorScheme) {
      var view = view(NotesSample.short, revealed: [])
      view.lines = NotesSample.lines
      view.transcriptExpanded = true
      let image = render(view, height: 1400, scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "short-lines-402-\(scheme.name)")
    }

    private func view(
      _ notes: SessionNotes, revealed: Set<String>, editable: Bool = false, isEditing: Bool = false
    ) -> NotesView {
      let hooks = NoteEditing(
        edit: { _, _, _ in }, delete: { _, _ in }, add: { _, _ in }, resolve: { _, _ in })
      var view = NotesView(
        notes: notes, transcript: NotesSample.transcript, date: NotesSample.date,
        revealed: revealed, editing: editable ? hooks : nil, isEditing: isEditing
      ) {}
      view.scrolls = false
      return view
    }
  }
#endif
