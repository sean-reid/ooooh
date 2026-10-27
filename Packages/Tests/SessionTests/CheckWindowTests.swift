import Foundation
import Governor
import State
import TestSupport
import Testing
import Transcription

@testable import Session

/// A check and a phrase see the last few utterances whether or not a compaction just ran.
@Suite struct CheckWindowTests {
  func segment(_ text: String, at index: Int, every gap: TimeInterval = 10) -> Segment {
    let start = TimeInterval(index) * gap
    return Segment(text: text, start: start, end: start + 1, isFinal: true)
  }

  @Test func theCheckThatTripsACompactionStillSeesTheWords() async throws {
    let decisions = CapturingDecisions(firingAt: 301)
    let phraser = CapturingPhraser()
    let loop = SessionLoop(
      config: .initial, policy: .init(everySeconds: 300, everyWords: 1000),
      dependencies: .init(decisions: decisions, compactor: PassthroughCompactor(), phraser: phraser)
    )
    await loop.handle(.segment(Segment(text: "one", start: 0, end: 1, isFinal: true)))
    await loop.handle(.segment(Segment(text: "two", start: 300, end: 301, isFinal: true)))
    await wait { await !phraser.recent.isEmpty }
    let result = await loop.finish()

    let compactions = result.records.compactMap {
      if case .compaction(let at, _) = $0 { at } else { nil }
    }
    #expect(compactions == [301])
    let inputs = await decisions.inputs
    #expect(inputs.map(\.signals.now) == [1, 301])
    #expect(inputs.last?.recentTranscript.map(\.text) == ["one", "two"])
    #expect(inputs.last?.state.currentThread == "one two")
    #expect(await phraser.recent == [["one", "two"]])
    #expect(await loop.uncompacted.isEmpty)
  }

  @Test func theWindowIsBoundedAndEndsAtTheLatestUtterance() async throws {
    let decisions = CapturingDecisions(firingAt: nil)
    let loop = SessionLoop(
      config: .warmedUp, policy: .init(everySeconds: 10_000, everyWords: 10_000),
      dependencies: .init(
        decisions: decisions, compactor: PassthroughCompactor(), phraser: TemplatePhraser()))
    let texts = (0..<10).map { "u\($0)" }
    for (index, text) in texts.enumerated() {
      await loop.handle(.segment(segment(text, at: index)))
    }

    let windows = await decisions.inputs.map { $0.recentTranscript.map(\.text) }
    #expect(windows.first == ["u0"])
    #expect(windows.last == Array(texts.suffix(SessionLoop.recentWindow)))
    #expect(windows.allSatisfy { $0.count <= SessionLoop.recentWindow })
    #expect(await loop.uncompacted.count == 10)
  }
  @Test func aPhraseSeesTheLastThreeLinesSaidOldestFirst() async throws {
    let decisions = ScriptedDecisionProvider { input in
      var answers = JevAnswers.quiet
      if input.signals.pauseLength == 0 {
        answers.goodMoment = .init(0.95)
        answers.intervention = .init(.deepen, confidence: 0.9)
      }
      return answers
    }
    let phraser = CapturingPhraser()
    let loop = SessionLoop(
      config: .warmedUp, policy: .init(everySeconds: 10_000, everyWords: 10_000),
      dependencies: .init(decisions: decisions, compactor: PassthroughCompactor(), phraser: phraser)
    )
    for index in 0..<5 {
      await loop.handle(.segment(segment("u\(index)", at: index, every: 150)))
    }
    await wait { await phraser.said.count == 5 }
    let result = await loop.finish()

    let lines = (1...4).map { "Line \($0), is it the queue or the sync?" }
    let spoken = result.records.compactMap {
      if case .prompt(_, _, let text) = $0 { text } else { nil }
    }
    #expect(spoken == lines)
    #expect(result.state.lastIntervention?.text == lines[3])
    #expect(
      await phraser.said == [
        [], [lines[0]], [lines[0], lines[1]], [lines[0], lines[1], lines[2]],
        [lines[1], lines[2], lines[3]],
      ])
  }
}

/// Keeps every input it was asked about, and fires a deepen at one utterance end.
actor CapturingDecisions: DecisionProvider {
  private(set) var inputs: [CheckInput] = []
  let firingAt: TimeInterval?

  init(firingAt: TimeInterval?) {
    self.firingAt = firingAt
  }

  func check(_ input: CheckInput) async throws -> JevAnswers {
    inputs.append(input)
    var answers = JevAnswers.quiet
    if let last = input.recentTranscript.last, last.end == firingAt, input.signals.pauseLength == 0
    {
      answers.goodMoment = .init(0.95)
      answers.intervention = .init(.deepen, confidence: 0.9)
    }
    return answers
  }
}

/// Keeps the recent words and the said lines each phrase was given, and answers with a numbered line.
actor CapturingPhraser: Phraser {
  private(set) var recent: [[String]] = []
  private(set) var said: [[String]] = []

  func phrase(
    _ kind: InterventionKind, state: CompactState, recent: [Segment],
    said: [CompactState.Intervention]
  ) async throws -> String {
    self.recent.append(recent.map(\.text))
    self.said.append(said.map(\.text))
    return "Line \(self.recent.count), is it the queue or the sync?"
  }
}
