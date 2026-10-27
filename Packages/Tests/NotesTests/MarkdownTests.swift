import Foundation
import State
import Testing
import Transcription

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

  @Test func putsTheStampedTranscriptLast() {
    let notes = SessionNotes(
      title: "Apartments", decisions: [NoteItem(id: "d1", text: "Park")])
    let transcript = [
      Segment(text: "Two options.", start: 12.8, end: 21, isFinal: true),
      Segment(text: "Park.", start: 180, end: 188, isFinal: true),
      Segment(text: "Still park.", start: 4502.2, end: 4510, isFinal: true),
    ]
    let md = notes.markdown(
      date: Date(timeIntervalSince1970: 1_792_900_000), timeZone: TimeZone(identifier: "UTC")!,
      transcript: transcript)
    #expect(
      md.hasSuffix(
        "## Decisions\n\n- Park\n\n## Transcript\n\n0:12 Two options.\n3:00 Park.\n75:02 Still park.\n"
      ))
    #expect(!notes.markdown(date: .now).contains("## Transcript"))
  }

  @Test func putsWhatTheAppAskedInPlaceWithItsKindAndMark() {
    let notes = SessionNotes(title: "Apartments")
    let transcript = [
      Segment(text: "Two options.", start: 12.8, end: 21, isFinal: true),
      Segment(text: "Park.", start: 180, end: 188, isFinal: true),
    ]
    let lines = [
      SpokenLine(text: "Done for now?", kind: .finishedQuestion, at: 190, spoken: false),
      SpokenLine(
        text: "What sits underneath that?", kind: .intervention(.deepen), at: 24.1, spoken: true,
        bad: true),
    ]
    let md = notes.markdown(
      date: Date(timeIntervalSince1970: 1_792_900_000), timeZone: TimeZone(identifier: "UTC")!,
      transcript: transcript, lines: lines)
    #expect(
      md.hasSuffix(
        "## Transcript\n\n0:12 Two options.\n0:24 [deepen, marked bad] What sits underneath that?\n"
          + "3:00 Park.\n3:10 [finished] Done for now?\n"))
    #expect(notes.markdown(date: .now, lines: lines).contains("## Transcript\n\n0:24 [deepen"))
  }

  @Test func aLineOnAnUtteranceStartGoesFirst() {
    let said = Segment(text: "Park.", start: 30, end: 31, isFinal: true)
    let line = SpokenLine(text: "Why park?", kind: .intervention(.clarify), at: 30, spoken: true)
    #expect([said].interleaved(with: [line]) == [.asked(line), .said(said)])
  }

  @Test func kindNamesRoundTrip() {
    for kind in InterventionKind.allCases {
      #expect(SpokenLine.Kind(name: kind.rawValue) == .intervention(kind))
    }
    #expect(SpokenLine.Kind(name: "finished") == .finishedQuestion)
    #expect(SpokenLine.Kind.finishedQuestion.name == "finished")
    #expect(SpokenLine.Kind(name: "wonder") == nil)
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
