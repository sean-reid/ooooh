import Foundation
import Testing

@testable import Notes

@Suite struct MarkdownTests {
  @Test func hidesEmptySectionsAndMarksResolved() {
    let notes = SessionNotes(
      title: "Cost and motivation",
      decisions: [NoteItem(id: "d1", text: "Ship the cheap version first")],
      openThreads: [NoteItem(id: "t1", text: "What the pricing page says", resolved: true)])
    let md = notes.markdown(
      date: Date(timeIntervalSince1970: 1_792_900_000), timeZone: TimeZone(identifier: "UTC")!)
    #expect(md.hasPrefix("# Cost and motivation\n\nOctober 25, 2026\n"))
    #expect(md.contains("## Decisions\n\n- Ship the cheap version first\n"))
    #expect(md.contains("## Open threads\n\n- [x] What the pricing page says\n"))
    #expect(!md.contains("## Ideas"))
  }

  @Test func putsTheSummaryUnderTheDate() {
    let notes = SessionNotes(
      title: "Apartments", summary: "Carver is cheaper, the park is closer.",
      openThreads: [NoteItem(id: "t1", text: "Ask about the lease length")])
    let md = notes.markdown(
      date: Date(timeIntervalSince1970: 1_792_900_000), timeZone: TimeZone(identifier: "UTC")!)
    #expect(
      md.contains("October 25, 2026\n\nCarver is cheaper, the park is closer.\n\n## Open threads"))
  }

  @Test func itemDecodesWithoutTheEditingFlags() throws {
    let json = Data(#"{"id": "a-b", "text": "A thing.", "span": null}"#.utf8)
    let item = try JSONDecoder().decode(NoteItem.self, from: json)
    #expect(item == NoteItem(id: "a-b", text: "A thing."))
    let round = try JSONDecoder().decode(
      NoteItem.self, from: JSONEncoder().encode(NoteItem(id: "c", text: "C", resolved: true)))
    #expect(round.resolved)
  }
}
