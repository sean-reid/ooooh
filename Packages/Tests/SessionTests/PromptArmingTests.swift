import Foundation
import Governor
import State
import Testing
import Transcription

@testable import Session

/// A decision at an utterance end waits for the pause to hold before it speaks.
@Suite struct PromptArmingTests {
  let base = SessionLoopTests()

  struct Harness {
    let clock = TestClock()
    let live: LiveSessionLoop
    let input: AsyncStream<TranscriptEvent>.Continuation
    var events: AsyncStream<SessionEvent>.Iterator

    init(_ decisions: any DecisionProvider) async {
      let (stream, continuation) = AsyncStream.makeStream(of: TranscriptEvent.self)
      input = continuation
      live = LiveSessionLoop(
        config: .initial,
        dependencies: .init(
          decisions: decisions, compactor: PassthroughCompactor(), phraser: TemplatePhraser()),
        transcriber: OpenTranscriber(stream: stream), clock: clock)
      events = live.events().makeAsyncIterator()
      await live.start()
    }

    /// Speaks one utterance and returns the events up to its speechEnded.
    mutating func say(_ text: String, from start: TimeInterval, to end: TimeInterval) async
      -> [SessionEvent]
    {
      input.yield(.speechStarted(at: start))
      input.yield(.segment(Segment(text: text, start: start, end: end, isFinal: true)))
      input.yield(.speechEnded(at: end))
      return await events.next(until: \.isSpeechEnded)
    }

    func advance(to seconds: TimeInterval) {
      clock.advance(to: .init(offset: .seconds(seconds)))
    }

    mutating func finish() async throws -> (events: [SessionEvent], result: SessionResult) {
      await live.end()
      let events = await self.events.rest()
      guard case .ended(let result) = try #require(events.last) else { throw Failure.noEnd }
      return (events, result)
    }

    enum Failure: Error { case noEnd }
  }

  /// Fires a good moment at every utterance end listed.
  func firing(_ kind: InterventionKind, at ends: Set<TimeInterval>) -> ScriptedDecisionProvider {
    ScriptedDecisionProvider { input in
      var answers = JevAnswers.quiet
      if let last = input.recentTranscript.last, input.signals.pauseLength == 0,
        ends.contains(last.end)
      {
        answers.goodMoment = .init(0.95)
        answers.intervention = .init(kind, confidence: 0.9)
      }
      return answers
    }
  }

  func armed(_ events: [SessionEvent]) -> [(at: TimeInterval, kind: ArmedPrompt)] {
    events.compactMap { if case .promptArmed(let at, let kind) = $0 { (at, kind) } else { nil } }
  }

  func spoken(_ events: [SessionEvent]) -> [(at: TimeInterval, kind: InterventionKind)] {
    events.compactMap {
      if case .promptRequested(let kind, _, let at) = $0 { (at, kind) } else { nil }
    }
  }

  func cancelled(_ events: [SessionEvent]) -> [TimeInterval] {
    events.compactMap { if case .promptCancelled(let at) = $0 { at } else { nil } }
  }

  func asked(_ events: [SessionEvent]) -> [TimeInterval] {
    events.compactMap { if case .askedIfFinished(let at) = $0 { at } else { nil } }
  }

  @Test func speaksOnceWhenThePauseHoldsForTheDelay() async throws {
    var h = await Harness(firing(.deepen, at: [0.5]))
    let start = await h.say("one", from: 0, to: 0.5)
    #expect(armed(start).map(\.at) == [0.5])
    #expect(armed(start).map(\.kind) == [.intervention(.deepen)])
    #expect(spoken(start).isEmpty)

    while h.clock.sleeping == 0 { await Task.yield() }
    h.advance(to: 1.9)
    #expect(h.clock.sleeping == 1)
    h.advance(to: 2.0)
    let fired = await h.events.next(until: \.isPromptRequested)
    #expect(spoken(fired).map(\.at) == [2.0])
    #expect((start + fired).contains { $0.isPromptPending })

    h.advance(to: 12)
    let (events, result) = try await h.finish()
    #expect(spoken(events).isEmpty)
    #expect(result.prompts.map(\.at) == [2.0])
    #expect(result.state.lastIntervention?.text == "What sits underneath that?")
    #expect(result.cancelledArms.isEmpty)
  }

  @Test func speechBeforeTheDelayCancelsAndNothingSpeaks() async throws {
    var h = await Harness(firing(.deepen, at: [0.5]))
    _ = await h.say("one", from: 0, to: 0.5)
    h.advance(to: 1.3)
    h.input.yield(.speechStarted(at: 1.3))
    let cut = await h.events.next(until: \.isPromptCancelled)
    #expect(cancelled(cut) == [1.3])

    h.advance(to: 6)
    _ = await h.say("two", from: 1.3, to: 3.0)
    h.advance(to: 10)
    let (events, result) = try await h.finish()
    #expect(spoken(events).isEmpty)
    #expect(result.prompts.isEmpty)
    #expect(result.cancelledArms == [1.3])
  }

  @Test func aCancelledArmDoesNotSuppressTheNextDecision() async throws {
    var h = await Harness(firing(.deepen, at: [0.5, 3.0]))
    _ = await h.say("one", from: 0, to: 0.5)
    h.advance(to: 1.3)
    h.input.yield(.speechStarted(at: 1.3))
    _ = await h.events.next(until: \.isPromptCancelled)
    let second = await h.say("two", from: 1.3, to: 3.0)
    #expect(armed(second).map(\.at) == [3.0])

    h.advance(to: 4.5)
    let fired = await h.events.next(until: \.isPromptRequested)
    #expect(spoken(fired).map(\.at) == [4.5])
    let (_, result) = try await h.finish()
    #expect(result.prompts.map(\.at) == [4.5])
    #expect(result.cancelledArms == [1.3])
  }

  @Test func theFinishedQuestionArmsTheSameWay() async throws {
    let finished = ScriptedDecisionProvider { input in
      var answers = JevAnswers.quiet
      if input.signals.pauseLength == 0 { answers.seemsFinished = .init(0.97) }
      return answers
    }
    var h = await Harness(finished)
    let start = await h.say("done", from: 0, to: 0.5)
    #expect(armed(start).map(\.kind) == [.finishedQuestion])
    #expect(asked(start).isEmpty)

    h.advance(to: 2.0)
    let fired = await h.events.next(until: \.isAskedIfFinished)
    #expect(asked(fired) == [2.0])
    let (_, result) = try await h.finish()
    #expect(result.finishedAsks == [2.0])
  }

  @Test func speechCancelsTheFinishedQuestionAndClearsTheGovernor() async {
    let finished = ScriptedDecisionProvider { input in
      var answers = JevAnswers.quiet
      if input.signals.pauseLength == 0, input.recentTranscript.count == 1 {
        answers.seemsFinished = .init(0.97)
      }
      return answers
    }
    let loop = SessionLoop(config: .initial, dependencies: base.deps(finished))
    await loop.handle(.segment(Segment(text: "done", start: 0, end: 0.5, isFinal: true)))
    #expect(await loop.governor.finishedAskedAt == 0.5)
    await loop.handle(.speechStarted(at: 1.3))
    #expect(await loop.governor.finishedAskedAt == nil)
    await loop.handle(.segment(Segment(text: "or not", start: 1.3, end: 3.0, isFinal: true)))
    await loop.pause(until: 40)
    let result = await loop.finish()
    #expect(result.finishedAsks.isEmpty)
    #expect(result.cancelledArms == [1.3])
    #expect(result.records.last == .ended(at: 3.0, byUser: true))
  }

  @Test func theFloorAndTheCheckIntervalStillApply() async throws {
    var h = await Harness(firing(.deepen, at: [0.5, 3.5]))
    _ = await h.say("one", from: 0, to: 0.5)
    h.advance(to: 2.0)
    _ = await h.events.next(until: \.isPromptRequested)
    h.advance(to: 2.6)
    let second = await h.say("two", from: 3.0, to: 3.5)
    #expect(armed(second).isEmpty)

    h.advance(to: 12)
    while h.clock.sleeping == 0 { await Task.yield() }
    let (events, result) = try await h.finish()
    #expect(spoken(events).isEmpty)
    #expect(result.prompts.map(\.at) == [2.0])
    let checks = result.records.compactMap {
      if case .check(let at, _, _, _) = $0 { at } else { nil }
    }
    #expect(checks == [0.5, 3.5, 8.5, 11.5])
  }

  @Test func armingCutsCollisionsOnTheShortFixture() async throws {
    let fixture = try base.fixture()
    let labels = Labels(fixture: "short", labels: [])
    func collisions(delay: TimeInterval) async -> (collisions: Int, cancelled: Int, prompts: Int) {
      var config = GovernorConfig.initial
      config.floor = .init(min: 0, max: 0)
      config.armingDelay = delay
      let every = ScriptedDecisionProvider { input in
        var answers = JevAnswers.quiet
        if input.signals.pauseLength == 0 {
          answers.goodMoment = .init(0.95)
          answers.intervention = .init(.deepen, confidence: 0.9)
        }
        return answers
      }
      let result = await FixtureDriver.run(
        fixture: fixture, config: config, dependencies: base.deps(every))
      let report = EvalReport.score(result, against: labels)
      return (report.collisions, report.cancelled, result.prompts.count)
    }
    let before = await collisions(delay: 0)
    let after = await collisions(delay: 1.5)
    #expect(before == (collisions: 15, cancelled: 0, prompts: 17))
    #expect(after == (collisions: 8, cancelled: 7, prompts: 10))
  }
}

extension SessionEvent {
  var isSpeechEnded: Bool { if case .speechEnded = self { true } else { false } }
  var isPromptPending: Bool { if case .promptPending = self { true } else { false } }
  var isPromptRequested: Bool { if case .promptRequested = self { true } else { false } }
  var isPromptCancelled: Bool { if case .promptCancelled = self { true } else { false } }
  var isAskedIfFinished: Bool { if case .askedIfFinished = self { true } else { false } }
}
