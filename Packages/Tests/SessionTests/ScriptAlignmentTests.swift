import Foundation
import Testing
import Transcription

@testable import Session

@Suite struct ScriptAlignmentTests {
  /// Four lines: the recognizer merges 1 and 2, splits 3 in two, and mishears a word in 0.
  let script = Script(
    name: "canned",
    summary: "A canned script for the alignment, with a merge, a split, and a misheard word.",
    utterances: [
      .init(text: "Okay, so the Carver place is cheaper.", pauseAfter: 0.5),
      .init(text: "A thousand less.", pauseAfter: 0.4, label: "clarify"),
      .init(text: "Which is real money.", pauseAfter: 6, label: "deepen"),
      .init(
        text: "But the commute is fifty five minutes each way and that is the whole day gone.",
        pauseAfter: 3, label: "finished"),
    ])

  let segments = [
    Segment(text: "Okay so the carpark place is cheaper", start: 0.2, end: 2.4, isFinal: true),
    Segment(text: "A thousand less which is real money", start: 2.9, end: 5.0, isFinal: true),
    Segment(text: "But the commute is 55 minutes each way", start: 11.1, end: 13.6, isFinal: true),
    Segment(text: "and that is the whole day gone", start: 14.7, end: 16.3, isFinal: true),
  ]

  @Test func tokensDropPunctuationAndCase() {
    #expect(
      ScriptAlignment.tokens("Okay, so it's REAL money.") == [
        "okay", "so", "it's", "real", "money",
      ])
    #expect(ScriptAlignment.tokens(" ... ") == [])
  }

  @Test func commonSubsequenceKeepsOrderAndSkipsMisheardWords() {
    let pairs = ScriptAlignment.commonSubsequence(["a", "b", "c", "d"], ["a", "x", "c", "b", "d"])
    #expect(pairs.map { $0.0 } == [0, 2, 3])
    #expect(pairs.map { $0.1 } == [0, 2, 4])
    #expect(ScriptAlignment.commonSubsequence([], ["a"]).isEmpty)
  }

  @Test func labelsMoveToTheEndOfTheSegmentHoldingTheLastWord() {
    let alignment = ScriptAlignment.align(script, to: segments)
    #expect(alignment.labels.fixture == "canned")
    #expect(
      alignment.labels.labels == [
        .init(utterance: 1, at: 5.0, kind: "deepen"),
        .init(utterance: 3, at: 16.3, kind: "finished"),
      ])
    #expect(
      alignment.dropped == [.init(segment: 1, kind: "clarify", utterance: 1, keptKind: "deepen")])
  }

  @Test func reportsMergesSplitsAndTheMatchRate() {
    let alignment = ScriptAlignment.align(script, to: segments)
    #expect(alignment.matches.map(\.segments) == [[0], [1], [1], [2, 3]])
    #expect(alignment.merged.map(\.segment) == [1])
    #expect(alignment.merged.map(\.utterances) == [[1, 2]])
    #expect(alignment.split.map(\.utterance) == [3])
    #expect(alignment.unmatched.isEmpty)
    #expect(alignment.scriptWords == 30)
    #expect(alignment.matchedWords == 27)
    #expect(alignment.recognizedWords == 29)
    #expect(
      alignment.report == [
        "script 4 utterances, 30 words; recognized 4 segments, 29 words; 27 matched (90%)",
        "split: utterance 3 across segments 2-3",
        "merged: segment 1 holds utterances 1, 2",
        "dropped: clarify from utterance 1, segment 1 keeps deepen",
        "labels: 2 placed, 1 dropped",
      ])
  }

  @Test func anUnmatchedLineLandsAfterTheNearestMatchedLineBefore() {
    var lost = script
    lost.utterances.insert(.init(text: "Hmm.", pauseAfter: 7, label: "leave"), at: 3)
    let alignment = ScriptAlignment.align(lost, to: segments)
    #expect(alignment.unmatched == [3])
    #expect(alignment.labels.labels.map(\.utterance) == [1, 3])
    #expect(alignment.labels.labels[0].kind == "leave")
    #expect(alignment.report.contains("unmatched: utterance 3"))
  }

  @Test func anUnmatchedOpeningLineLandsBeforeTheFirstMatch() {
    var lost = script
    lost.utterances.insert(.init(text: "Right.", pauseAfter: 5, label: "reflect"), at: 0)
    let alignment = ScriptAlignment.align(lost, to: segments)
    #expect(alignment.labels.labels.first == .init(utterance: 0, at: 2.4, kind: "reflect"))
  }

  @Test func scriptsDecodeWithOptionalLabelAndNote() throws {
    let json = """
      {"name": "x", "summary": "s", "utterances": [
        {"text": "a", "pauseAfter": 1},
        {"text": "b", "pauseAfter": 2.5, "label": "leave", "note": "long"}
      ]}
      """
    let script = try JSONDecoder().decode(Script.self, from: Data(json.utf8))
    #expect(script.utterances[0].label == nil)
    #expect(script.utterances[1] == .init(text: "b", pauseAfter: 2.5, label: "leave", note: "long"))
  }
}
