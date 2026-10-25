import Foundation
import Testing

@testable import Notes

@Suite struct MarkdownTests {
  @Test func hidesEmptySectionsAndMarksResolved() {
    let notes = SessionNotes(
      title: "Cost and motivation",
      decisions: [NoteItem(id: "d1", text: "Ship the cheap version first")],
      openThreads: [NoteItem(id: "t1", text: "What the pricing page says", resolved: true)])
    let md = notes.markdown(date: Date(timeIntervalSince1970: 1_792_900_000))
    #expect(md.hasPrefix("# Cost and motivation\n\nOctober 24, 2026\n"))
    #expect(md.contains("## Decisions\n\n- Ship the cheap version first\n"))
    #expect(md.contains("## Open threads\n\n- [x] What the pricing page says\n"))
    #expect(!md.contains("## Ideas"))
  }
}
