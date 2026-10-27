#if canImport(UIKit)
  import Design
  import Notes
  import SnapshotTesting
  import SwiftUI
  import Testing
  import UIKit

  @testable import NotesUI

  /// The transcript section alone, on the sky, at the width the notes suite uses.
  @MainActor
  @Suite struct TranscriptSnapshotTests {
    @Test(arguments: [false, true], [ColorScheme.dark, .light])
    func transcript(expanded: Bool, scheme: ColorScheme) {
      let image = render(section(expanded: expanded), scheme: scheme)
      assertSnapshot(
        of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
        named: "\(expanded ? "expanded" : "collapsed")-402-\(scheme.name)")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func transcriptWithLines(scheme: ColorScheme) {
      let image = render(section(expanded: true, lines: NotesSample.lines), scheme: scheme)
      assertSnapshot(
        of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
        named: "lines-402-\(scheme.name)")
    }

    @Test func transcriptAccessibility3() {
      let image = render(section(expanded: true), scheme: .dark, type: .accessibility3)
      assertSnapshot(
        of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
        named: "expanded-402-accessibility3-dark")
    }

    @Test func lengthCountsUtterancesAndRunsToTheLastWord() {
      #expect(TranscriptView(transcript: NotesSample.transcript).length == "6 utterances, 3m 8s")
      #expect(
        TranscriptView(transcript: [NotesSample.transcript[0]]).length == "1 utterance, 21s")
    }

    /// Laid out at its natural height and clipped, the way NotesView renders for a snapshot,
    /// so a frame shorter than the text shows the overflow cut off rather than truncated.
    private func section(expanded: Bool, lines: [SpokenLine] = []) -> some View {
      ZStack(alignment: .top) {
        Palette.sky.ignoresSafeArea()
        GeometryReader { _ in
          TranscriptView(transcript: NotesSample.transcript, lines: lines, expanded: expanded)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .fixedSize(horizontal: false, vertical: true)
        }
        .clipped()
      }
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
