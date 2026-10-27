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

    private func view(_ notes: SessionNotes, revealed: Set<String>) -> NotesView {
      var view = NotesView(
        notes: notes, transcript: NotesSample.transcript, date: NotesSample.date,
        revealed: revealed
      ) {}
      view.scrolls = false
      return view
    }
  }
#endif
