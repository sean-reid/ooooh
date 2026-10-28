#if DEBUG
  import Foundation
  import Notes
  import OSLog
  import Persistence
  import Session
  import Transcription

  /// `-reset-store 1` empties the store at launch. `-seed-history 1` adds one finished session with
  /// the notes in fixtures/demo/history.notes.json, two open threads among them, and two lines
  /// the app asked, one marked bad, so the UI tests see history, the carryover card, and the
  /// transcript without the Worker.
  enum DebugHistory {
    static let seededLines = [
      SpokenLine(
        text: "What does the extra thousand a month buy you?", kind: .intervention(.clarify),
        at: 62, spoken: true),
      SpokenLine(
        text: "Is this really about the money?", kind: .intervention(.challenge), at: 190,
        spoken: false, bad: true),
    ]

    private static let log = Logger(subsystem: "com.seanreid.ooooh", category: "debug-history")

    static var notes: SessionNotes? { try? bundledNotes() }

    static func bundledNotes() throws -> SessionNotes {
      try JSONDecoder().decode(SessionNotes.self, from: Data(contentsOf: bundled("history.notes")))
    }

    /// The fixture Demo replays and the seed runs through the loop.
    static func demoFixtureURL() throws -> URL { try bundled("decision.fixture") }

    static func demoFixture() throws -> FixtureTranscriber.Fixture {
      try JSONDecoder().decode(
        FixtureTranscriber.Fixture.self, from: Data(contentsOf: demoFixtureURL()))
    }

    private static func bundled(_ name: String) throws -> URL {
      guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
      }
      return url
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
      do {
        let notes = try bundledNotes()
        let result = await FixtureDriver.run(
          fixture: try demoFixture(), config: .initial,
          dependencies: .init(
            decisions: SilentDecisionProvider(), compactor: PassthroughCompactor(),
            phraser: TemplatePhraser()))
        try await store.save(
          result: result, lines: seededLines, notes: notes, title: notes.title,
          startedAt: .now.addingTimeInterval(-86_400))
      } catch {
        log.error("Seeding history failed: \(String(describing: error), privacy: .public)")
      }
    }
  }
#endif
