import Foundation
import Governor
import State
import Testing
import Transcription

@testable import Session

@Suite struct SessionLoopTests {
  static let fixtureURL = Bundle.module.url(
    forResource: "short", withExtension: "json", subdirectory: "Fixtures")!

  func fixture() throws -> FixtureTranscriber.Fixture {
    try JSONDecoder().decode(
      FixtureTranscriber.Fixture.self, from: Data(contentsOf: Self.fixtureURL))
  }

  func deps(_ decisions: any DecisionProvider) -> SessionLoop.Dependencies {
    .init(decisions: decisions, compactor: PassthroughCompactor(), phraser: TemplatePhraser())
  }

  /// Fires a good moment while the speaker is on the utterance ending at `end`.
  func firing(
    _ kind: InterventionKind, afterUtteranceEnding end: TimeInterval,
    finishedAt: TimeInterval? = nil
  )
    -> ScriptedDecisionProvider
  {
    ScriptedDecisionProvider { input in
      var answers = JevAnswers.quiet
      if let last = input.recentTranscript.last, last.end == end {
        answers.goodMoment = .init(0.95)
        answers.intervention = .init(kind, confidence: 0.9)
      }
      if let finishedAt, input.signals.now >= finishedAt {
        answers.seemsFinished = .init(0.97)
      }
      return answers
    }
  }

  @Test func silentProviderNeverPromptsAndEndsByUser() async throws {
    let result = await FixtureDriver.run(
      fixture: try fixture(), config: .initial, dependencies: deps(SilentDecisionProvider()))
    #expect(result.prompts.isEmpty)
    #expect(result.finishedAsks.isEmpty)
    #expect(result.records.last == .ended(at: 49.8, byUser: true))
    #expect(result.transcript.count == 10)
    let checks = result.records.filter { if case .check = $0 { true } else { false } }
    #expect(checks.count > 10)
  }

  @Test func promptsOnceAtTheScriptedMomentWithTemplateText() async throws {
    let result = await FixtureDriver.run(
      fixture: try fixture(), config: .initial,
      dependencies: deps(firing(.deepen, afterUtteranceEnding: 14.0)))
    #expect(result.prompts.count == 1)
    #expect(result.prompts.first?.kind == .deepen)
    #expect(result.prompts.first?.at == 14.0)
    #expect(result.state.lastIntervention?.text == "What sits underneath that?")
  }

  @Test func wrapsUpAfterFinishedThenSilence() async throws {
    let result = await FixtureDriver.run(
      fixture: try fixture(), config: .initial,
      dependencies: deps(firing(.clarify, afterUtteranceEnding: -1, finishedAt: 49.8)))
    #expect(result.finishedAsks == [49.8])
    guard case .ended(let at, let byUser) = result.records.last! else {
      Issue.record("session did not end")
      return
    }
    #expect(byUser == false)
    #expect(at >= 49.8 + 30)
  }

  @Test func compactsWhenPolicySaysAndKeepsRawWindowSmall() async throws {
    let result = await FixtureDriver.run(
      fixture: try fixture(), config: .initial, policy: .init(everySeconds: 20, everyWords: 1000),
      dependencies: deps(SilentDecisionProvider()))
    let compactions = result.records.filter { if case .compaction = $0 { true } else { false } }
    #expect(compactions.count == 2)
    #expect(result.state.currentThread.contains("done for now"))
  }

  @Test func densityDropsThroughAPause() async {
    let loop = SessionLoop(config: .initial, dependencies: deps(SilentDecisionProvider()))
    await loop.handle(.segment(Segment(text: "a b c", start: 0, end: 10, isFinal: true)))
    let dense = await loop.density(at: 10)
    let sparse = await loop.density(at: 40)
    #expect(dense == 1)
    #expect(abs(sparse - 0.25) < 0.001)
  }
}
