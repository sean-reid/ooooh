import Foundation
import Governor
import State
import TestSupport
import Testing
import Transcription

@testable import Session

extension GovernorConfig {
  /// The shipped numbers past the warm-up, so a scripted moment inside the first minute arms.
  static var warmedUp: GovernorConfig {
    var config = initial
    config.warmUp = 0
    return config
  }
}

@Suite struct SessionLoopTests {
  func fixture() throws -> FixtureTranscriber.Fixture {
    try Bundle.module.fixture("short.json", as: FixtureTranscriber.Fixture.self)
  }

  func deps(_ decisions: any DecisionProvider) -> SessionLoop.Dependencies {
    .init(decisions: decisions, compactor: PassthroughCompactor(), phraser: TemplatePhraser())
  }

  /// Fires a good moment while the speaker is on an utterance ending at one of `ends`.
  func firing(
    _ kind: InterventionKind, afterUtterancesEnding ends: Set<TimeInterval>,
    finishedAt: TimeInterval? = nil
  )
    -> ScriptedDecisionProvider
  {
    ScriptedDecisionProvider { input in
      var answers = JevAnswers.quiet
      if let last = input.recentTranscript.last, ends.contains(last.end) {
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
    #expect(result.records.last == .ended(at: 87.8, byUser: true))
    #expect(result.transcript.count == 17)
    let checks = result.records.filter { if case .check = $0 { true } else { false } }
    #expect(checks.count > 10)
  }

  @Test func promptsOnceAtTheScriptedMomentWithTemplateText() async throws {
    let result = await FixtureDriver.run(
      fixture: try fixture(), config: .initial,
      dependencies: deps(firing(.deepen, afterUtterancesEnding: [80.6])))
    #expect(result.prompts.count == 1)
    #expect(result.prompts.first?.kind == .deepen)
    #expect(result.prompts.first?.at == 83.1)
    #expect(result.state.lastIntervention?.text == "What sits underneath that?")
    #expect(result.records.contains(.promptArmed(at: 80.6, kind: .intervention(.deepen))))
  }

  @Test func aMomentInsideTheWarmUpIsHeldAndTheNextOneAfterItPrompts() async throws {
    let result = await FixtureDriver.run(
      fixture: try fixture(), config: .initial,
      dependencies: deps(firing(.deepen, afterUtterancesEnding: [14.0, 80.6])))
    let decided = result.records.compactMap {
      if case .check(let at, _, _, let decision) = $0, [14.0, 80.6].contains(at) {
        decision
      } else {
        nil
      }
    }
    #expect(decided == [.wait, .prompt(.deepen)])
    let armed = result.records.compactMap {
      if case .promptArmed(let at, _) = $0 { at } else { nil }
    }
    #expect(armed == [80.6])
    #expect(result.prompts.map(\.at) == [83.1])
  }

  @Test func wrapsUpAfterFinishedThenSilence() async throws {
    let result = await FixtureDriver.run(
      fixture: try fixture(), config: .initial,
      dependencies: deps(firing(.clarify, afterUtterancesEnding: [], finishedAt: 87.8)))
    #expect(result.records.contains(.promptArmed(at: 87.8, kind: .finishedQuestion)))
    #expect(result.finishedAsks == [90.3])
    guard case .ended(let at, let byUser) = result.records.last! else {
      Issue.record("session did not end")
      return
    }
    #expect(byUser == false)
    #expect(at >= 87.8 + 30)
  }

  @Test func compactsWhenPolicySaysAndKeepsRawWindowSmall() async throws {
    let result = await FixtureDriver.run(
      fixture: try fixture(), config: .initial, policy: .init(everySeconds: 20, everyWords: 1000),
      dependencies: deps(SilentDecisionProvider()))
    let compactions = result.records.filter { if case .compaction = $0 { true } else { false } }
    #expect(compactions.count == 4)
    #expect(result.state.currentThread.contains("done for now"))
  }

  @Test func aLongPauseGetsTheScheduleThenTheFinishedQuestionThenTheEnd() async {
    let loop = SessionLoop(config: .initial, dependencies: deps(SilentDecisionProvider()))
    await loop.handle(.segment(Segment(text: "a b c", start: 0, end: 10, isFinal: true)))
    for now in stride(from: 11.0, through: 610, by: 1) {
      await loop.pause(until: now)
    }
    let checks = await loop.records.compactMap {
      if case .check(let at, _, _, _) = $0 { at } else { nil }
    }
    #expect(checks == [10, 15, 21, 30, 55, 85])
    #expect(await loop.records.contains(.askedIfFinished(at: 55)))
    #expect(await loop.records.last == .ended(at: 85, byUser: false))
    #expect(await loop.nextCheckAt == nil)
  }

  @Test func speechBeforeTheLongSilenceRestartsTheSchedule() async {
    let loop = SessionLoop(config: .initial, dependencies: deps(SilentDecisionProvider()))
    await loop.handle(.segment(Segment(text: "a b c", start: 0, end: 10, isFinal: true)))
    for now in stride(from: 11.0, through: 50, by: 1) {
      await loop.pause(until: now)
    }
    #expect(await loop.nextCheckAt == 55)
    await loop.handle(.segment(Segment(text: "d", start: 52, end: 53, isFinal: true)))
    #expect(await loop.nextCheckAt == 58)
    #expect(
      await loop.records.contains { if case .askedIfFinished = $0 { true } else { false } } == false
    )
  }

  @Test func theFinishedQuestionEndsTheSessionAfterOneMoreCheck() async {
    let finished = ScriptedDecisionProvider { input in
      var answers = JevAnswers.quiet
      if input.signals.pauseLength == 0 { answers.seemsFinished = .init(0.97) }
      return answers
    }
    let loop = SessionLoop(config: .initial, dependencies: deps(finished))
    await loop.handle(.segment(Segment(text: "done", start: 0, end: 10, isFinal: true)))
    #expect(await loop.nextTick == 12.5)
    await loop.pause(until: 12.5)
    #expect(await loop.nextTick == 40)
    await loop.pause(until: 40)
    let checks = await loop.records.compactMap {
      if case .check(let at, _, _, _) = $0 { at } else { nil }
    }
    #expect(checks == [10, 40])
    #expect(await loop.records.last == .ended(at: 40, byUser: false))
    #expect(await loop.nextTick == nil)
  }

  @Test func endDuringACompactionWaitsForItInsteadOfCompactingAgain() async throws {
    let compactor = BlockingCompactor()
    let loop = SessionLoop(
      config: .initial,
      dependencies: .init(
        decisions: SilentDecisionProvider(), compactor: compactor, phraser: TemplatePhraser()))
    await loop.handle(.segment(Segment(text: "first", start: 0, end: 1, isFinal: true)))
    let second = Segment(text: "and the last", start: 300, end: 301, isFinal: true)
    let handling = Task { await loop.handle(.segment(second)) }
    await wait { await compactor.calls.count >= 1 }
    let ending = Task { await loop.finish() }
    await wait { await loop.ending }
    await compactor.release()
    await handling.value
    let result = await ending.value

    #expect(await compactor.calls == [["first", "and the last"]])
    let compactions = result.records.filter { if case .compaction = $0 { true } else { false } }
    #expect(compactions.count == 1)
    #expect(result.records.last == .ended(at: 301, byUser: true))
    #expect(result.state.currentThread == "first and the last")
    #expect(await loop.uncompacted.isEmpty)
  }

  @Test func aSegmentHeardDuringACompactionStaysForTheNextOne() async throws {
    let compactor = BlockingCompactor()
    let loop = SessionLoop(
      config: .initial,
      dependencies: .init(
        decisions: SilentDecisionProvider(), compactor: compactor, phraser: TemplatePhraser()))
    let first = Task {
      await loop.handle(.segment(Segment(text: "first", start: 300, end: 301, isFinal: true)))
    }
    await wait { await compactor.calls.count >= 1 }
    let second = Task {
      await loop.handle(.segment(Segment(text: "second", start: 302, end: 303, isFinal: true)))
    }
    await wait { await loop.uncompacted.count >= 2 }
    await compactor.release()
    await first.value
    await second.value

    #expect(await compactor.calls == [["first"]])
    #expect(await loop.uncompacted.map(\.text) == ["second"])
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

/// Parks every compaction until the test releases it, and records what each one was given.
actor BlockingCompactor: Compactor {
  private(set) var calls: [[String]] = []
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var open = false

  func compact(state: CompactState, transcript: [Segment]) async throws -> StatePatch {
    calls.append(transcript.map(\.text))
    if !open {
      await withCheckedContinuation { waiters.append($0) }
    }
    return StatePatch(currentThread: transcript.map(\.text).joined(separator: " "))
  }

  func release() {
    open = true
    for waiter in waiters { waiter.resume() }
    waiters.removeAll()
  }
}
