#if DEBUG
  import Foundation
  import Notes
  import Persistence
  import Session
  import Transcription

  /// `-reset-store 1` empties the store at launch. `-seed-history 1` adds one finished session with
  /// notes and two open threads, so the UI tests see history and the carryover card without the Worker.
  enum DebugHistory {
    static let notes = SessionNotes(
      title: "Carver Street or the park",
      decisions: [
        NoteItem(
          id: "make-the-case", text: "Make the case for the park place tonight with the numbers",
          span: .init(start: 487, end: 510))
      ],
      insights: [
        NoteItem(
          id: "six-hundred-not-thousand",
          text: "The real gap is six hundred a month, not a thousand",
          span: .init(start: 245, end: 256))
      ],
      openThreads: [
        NoteItem(
          id: "time-versus-money", text: "How Sam and I weight time against money",
          span: .init(start: 440, end: 454)),
        NoteItem(
          id: "eighteen-month-lease", text: "Whether the eighteen month lease is a problem",
          span: .init(start: 389, end: 415)),
      ])

    static func apply(to store: SessionStore) async {
      let defaults = UserDefaults.standard
      if defaults.bool(forKey: "reset-store") {
        try? await store.deleteEverything()
      }
      if defaults.bool(forKey: "seed-history") {
        await seed(store)
      }
    }

    private static func seed(_ store: SessionStore) async {
      guard let url = Bundle.main.url(forResource: "decision.fixture", withExtension: "json"),
        let data = try? Data(contentsOf: url),
        let fixture = try? JSONDecoder().decode(FixtureTranscriber.Fixture.self, from: data)
      else { return }
      let result = await FixtureDriver.run(
        fixture: fixture, config: .initial,
        dependencies: .init(
          decisions: SilentDecisionProvider(), compactor: PassthroughCompactor(),
          phraser: TemplatePhraser()))
      try? await store.save(
        result: result, notes: notes, title: notes.title,
        startedAt: .now.addingTimeInterval(-86_400))
    }
  }
#endif
