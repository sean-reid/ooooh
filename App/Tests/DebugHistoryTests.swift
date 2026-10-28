import Governor
import Notes
import Session
import TestSupport
import Testing
import Transcription

@testable import ooooh

/// The seeded history decodes fixtures/demo/history.notes.json from the app bundle; HistoryTests
/// names its title and its two open threads. Demo replays decision.fixture.json from the same
/// bundle, so a fixture that stops decoding fails here instead of leaving Demo a no-op.
@Suite struct DebugHistoryTests {
  @Test func theDemoFixtureDecodesThroughTheTranscriber() throws {
    let fixture = try DebugHistory.demoFixture()
    #expect(fixture.segments.count == 35)
    #expect(fixture.segments.allSatisfy { $0.isFinal && $0.start < $0.end })
    #expect(fixture.segments.first?.text.hasPrefix("Right, apartments.") == true)
    _ = try FixtureTranscriber(contentsOf: try DebugHistory.demoFixtureURL())
  }

  @MainActor
  @Test func theDemoFixtureRunsToTheEndOfASession() async throws {
    var environment = SessionController.Environment(workerURL: nil)
    environment.audio = .none
    environment.config = .initial
    environment.dependencies = .init(
      decisions: SilentDecisionProvider(), compactor: PassthroughCompactor(),
      phraser: TemplatePhraser())
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(try DebugHistory.demoFixtureURL(), speed: .infinity))
    await wait { controller.stage == .ended }
    #expect(controller.stage == .ended)
    #expect(controller.result?.transcript.count == 35)
  }

  /// HistoryTests opens the seeded transcript and reads two lines the app asked, one marked bad,
  /// so both sit inside the fixture's run.
  @Test func seededLinesFallInsideTheDemoFixture() throws {
    let end = try #require(DebugHistory.demoFixture().segments.map(\.end).max())
    let lines = DebugHistory.seededLines
    #expect(lines.count == 2)
    #expect(lines.allSatisfy { $0.at > 0 && $0.at < end })
    #expect(lines.filter(\.bad).count == 1)
  }

  @Test func bundledNotesAreTheCarverStreetSession() throws {
    let notes = try DebugHistory.bundledNotes()
    #expect(DebugHistory.notes == notes)
    #expect(notes.title == "Carver Street or the park")
    #expect(
      notes.openThreads.map(\.text) == [
        "How Sam and I weight time against money",
        "Whether the eighteen month lease is a problem",
      ])
    #expect(notes.openThreads.map(\.id) == ["time-versus-money", "eighteen-month-lease"])
    #expect(notes.decisions.map(\.id) == ["make-the-case"])
    #expect(notes.insights.map(\.id) == ["six-hundred-not-thousand"])
    #expect(notes.insights.map(\.text) == ["The real gap is six hundred a month, not a thousand"])
    let spans = notes.sections.flatMap(\.items).compactMap(\.span)
    #expect(spans.count == 4)
    #expect(spans.allSatisfy { $0.start > 0 && $0.start < $0.end })
  }
}
