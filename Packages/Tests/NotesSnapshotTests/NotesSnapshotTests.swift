#if canImport(UIKit)
  import SnapshotTesting
  import SwiftUI
  import Testing
  import UIKit

  @testable import Notes

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
      assertSnapshot(
        of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
        named: "\(sample.name)-402-\(scheme.name)")
    }

    @Test(arguments: samples)
    func notesAccessibility3(sample: Sample) {
      let image = render(
        view(sample.notes, revealed: sample.revealed), scheme: .dark, type: .accessibility3)
      assertSnapshot(
        of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
        named: "\(sample.name)-402-accessibility3-dark")
    }

    private func view(_ notes: SessionNotes, revealed: Set<String>) -> NotesView {
      var view = NotesView(
        notes: notes, transcript: NotesSample.transcript, date: NotesSample.date,
        revealed: revealed
      ) {}
      view.scrolls = false
      return view
    }

    private func render(
      _ view: some View, width: CGFloat = 402, height: CGFloat = 874, scheme: ColorScheme,
      type: DynamicTypeSize = .large
    ) -> UIImage {
      let renderer = ImageRenderer(
        content: view.frame(width: width, height: height).environment(\.colorScheme, scheme)
          .dynamicTypeSize(type))
      renderer.scale = 2
      renderer.proposedSize = ProposedViewSize(width: width, height: height)
      return renderer.uiImage ?? UIImage()
    }
  }

  extension ColorScheme {
    fileprivate var name: String { self == .dark ? "dark" : "light" }
  }
#endif
