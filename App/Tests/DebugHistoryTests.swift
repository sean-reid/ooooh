import Notes
import Testing

@testable import ooooh

/// The seeded history decodes fixtures/demo/history.notes.json from the app bundle; HistoryTests
/// names its title and its two open threads.
@Suite struct DebugHistoryTests {
  @Test func bundledNotesAreTheCarverStreetSession() throws {
    let notes = try #require(DebugHistory.notes)
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
