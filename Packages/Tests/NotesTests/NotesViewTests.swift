import Testing
import Transcription

@testable import Notes

@Suite struct NotesViewTests {
  let transcript = [
    Segment(text: "First thing.", start: 0, end: 4, isFinal: true),
    Segment(text: "Second thing.", start: 5, end: 9, isFinal: true),
    Segment(text: "Third thing.", start: 10, end: 14, isFinal: true),
  ]

  @Test func spanTextJoinsEveryOverlappingSegment() {
    #expect(TranscriptSpan(start: 6, end: 11).text(in: transcript) == "Second thing. Third thing.")
    #expect(TranscriptSpan(start: 4, end: 4).text(in: transcript) == "First thing.")
    #expect(TranscriptSpan(start: 20, end: 30).text(in: transcript) == "")
  }
}
