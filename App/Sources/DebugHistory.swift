#if DEBUG
  import Foundation
  import Notes
  import Persistence
  import Session
  import Transcription

  /// `-reset-store 1` empties the store at launch. `-seed-history 1` adds one finished session with
  /// the notes in fixtures/demo/history.notes.json, two open threads among them, so the UI tests
  /// see history and the carryover card without the Worker.
  enum DebugHistory {
    static var notes: SessionNotes? {
      guard let url = Bundle.main.url(forResource: "history.notes", withExtension: "json"),
        let data = try? Data(contentsOf: url)
      else { return nil }
      return try? JSONDecoder().decode(SessionNotes.self, from: data)
    }

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
      guard let notes,
        let url = Bundle.main.url(forResource: "decision.fixture", withExtension: "json"),
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
