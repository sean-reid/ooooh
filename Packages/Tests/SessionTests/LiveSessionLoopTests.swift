import Foundation
import Governor
import State
import TestSupport
import Testing
import Transcription

@testable import Session

@Suite struct LiveSessionLoopTests {
  let base = SessionLoopTests()

  func collect(_ live: LiveSessionLoop) async -> [SessionEvent] {
    var events: [SessionEvent] = []
    for await event in live.events() { events.append(event) }
    return events
  }

  func result(of events: [SessionEvent]) throws -> SessionResult {
    guard case .ended(let result) = try #require(events.last) else {
      throw TestError.noEnd
    }
    return result
  }

  enum TestError: Error { case noEnd }

  @Test func matchesTheFixtureDriverAtInfiniteSpeed() async throws {
    let fixture = try base.fixture()
    let deps = base.deps(base.firing(.deepen, afterUtteranceEnding: 14.0))
    let expected = await FixtureDriver.run(fixture: fixture, config: .initial, dependencies: deps)

    let live = LiveSessionLoop(
      config: .initial, dependencies: deps, transcriber: FixtureTranscriber(fixture: fixture))
    await live.start()
    let events = await collect(live)
    let result = try result(of: events)

    let lastEnd = try #require(fixture.segments.last).end
    #expect(result.records == expected.records.filter { $0.at <= lastEnd })
    #expect(result.records.count > 10)
    #expect(result.transcript == expected.transcript)
    #expect(result.state == expected.state)

    let utterances = events.filter { if case .utterance = $0 { true } else { false } }
    #expect(utterances.count == 17)
    let armed = events.compactMap {
      if case .promptArmed(let at, let k) = $0 { (at, k) } else { nil }
    }
    #expect(armed.count == 1)
    #expect(armed.first?.0 == 14.0)
    #expect(armed.first?.1 == .intervention(.deepen))
    let prompts = events.compactMap {
      if case .promptRequested(_, let text, let at) = $0 { (text, at) } else { nil }
    }
    #expect(prompts.count == 1)
    #expect(prompts.first?.0 == "What sits underneath that?")
    #expect(prompts.first?.1 == 15.5)
  }

  @Test func timerFiresPauseChecksWhileNoSpeechArrives() async throws {
    var config = GovernorConfig.initial
    config.silenceChecks = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.5]
    let clock = TestClock()
    let (events, continuation) = AsyncStream.makeStream(of: TranscriptEvent.self)
    let open = OpenTranscriber(stream: events, input: continuation)
    let live = LiveSessionLoop(
      config: config, dependencies: base.deps(SilentDecisionProvider()), transcriber: open,
      clock: clock)
    await live.start()
    var iterator = live.events().makeAsyncIterator()
    continuation.yield(.speechStarted(at: 0))
    continuation.yield(.segment(Segment(text: "one", start: 0, end: 0.5, isFinal: true)))
    continuation.yield(.speechEnded(at: 0.5))
    _ = await iterator.next(until: \.isSpeechEnded)
    await wait { clock.sleeping > 0 }
    clock.advance(to: .init(offset: .seconds(2.3)))
    await wait { clock.sleeping > 0 }
    await live.end()
    let result = try result(of: await iterator.rest())

    let pauses = result.records.compactMap { record -> TimeInterval? in
      if case .check(let at, _, _, let decision) = record, at > 0.5, decision == .wait {
        at
      } else {
        nil
      }
    }
    #expect(pauses == [1.0, 1.25, 1.5, 1.75, 2.0, 2.25])
    #expect(result.records.last == .ended(at: 0.5, byUser: true))
  }

  @Test func endingEarlyKeepsWhatWasHeard() async throws {
    let fixture = try base.fixture()
    let live = LiveSessionLoop(
      config: .initial, dependencies: base.deps(SilentDecisionProvider()),
      transcriber: FixtureTranscriber(fixture: fixture, speed: 1))
    await live.start()
    var heard: [Segment] = []
    for await event in live.events() {
      if case .utterance(let segment) = event {
        heard.append(segment)
        Task { await live.end() }
      }
      if case .ended(let result) = event {
        #expect(result.transcript == heard)
        #expect(result.transcript.count == 1)
        #expect(result.records.last == .ended(at: 4.2, byUser: true))
        #expect(result.state.currentThread.hasSuffix(heard[0].text.suffix(50)))
      }
    }
  }

  @Test func endKeepsTheSegmentTheTranscriberFinalisesOnStop() async throws {
    let clock = TestClock()
    let (stream, input) = AsyncStream.makeStream(of: TranscriptEvent.self)
    let last = Segment(
      text: "and that is the last thing I said", start: 1.0, end: 3.5, isFinal: true)
    let live = LiveSessionLoop(
      config: .initial, dependencies: base.deps(SilentDecisionProvider()),
      transcriber: FinalisingTranscriber(stream: stream, input: input, last: last), clock: clock)
    await live.start()
    var iterator = live.events().makeAsyncIterator()
    input.yield(.speechStarted(at: 0))
    input.yield(.segment(Segment(text: "first", start: 0, end: 0.5, isFinal: true)))
    input.yield(.speechEnded(at: 0.5))
    _ = await iterator.next(until: \.isSpeechEnded)
    input.yield(.speechStarted(at: 1.0))
    input.yield(.segment(Segment(text: "and that", start: 1.0, end: 1.4, isFinal: false)))
    await wait { clock.sleeping > 0 }
    await live.end()
    let events = await iterator.rest()
    let result = try result(of: events)

    #expect(result.transcript.map(\.text) == ["first", "and that is the last thing I said"])
    let heard = events.compactMap { if case .utterance(let s) = $0 { s.text } else { nil } }
    #expect(heard == ["and that is the last thing I said"])
    #expect(result.state.currentThread.hasSuffix("the last thing I said"))
    #expect(result.records.last == .ended(at: 3.5, byUser: true))
    let checks = result.records.filter { if case .check = $0 { true } else { false } }
    #expect(checks.count == 1)
    #expect(clock.sleeping == 0)
  }

  @Test func endGivesUpOnATranscriberThatNeverEndsItsStream() async throws {
    let clock = TestClock()
    let (events, input) = AsyncStream.makeStream(of: TranscriptEvent.self)
    let live = LiveSessionLoop(
      config: .initial, dependencies: base.deps(SilentDecisionProvider()),
      transcriber: StuckTranscriber(stream: events), clock: clock)
    await live.start()
    var iterator = live.events().makeAsyncIterator()
    input.yield(.speechStarted(at: 0))
    input.yield(.segment(Segment(text: "one", start: 0, end: 0.5, isFinal: true)))
    input.yield(.speechEnded(at: 0.5))
    _ = await iterator.next(until: \.isSpeechEnded)
    await wait { clock.sleeping > 0 }
    let ending = Task { await live.end() }
    await wait { clock.deadlines.contains(LiveSessionLoop.stopGrace) }
    #expect(clock.deadlines == [LiveSessionLoop.stopGrace])
    clock.advance(by: LiveSessionLoop.stopGrace - .milliseconds(1))
    #expect(clock.sleeping == 1)
    clock.advance(by: .milliseconds(1))
    await ending.value
    let result = try result(of: await iterator.rest())

    #expect(result.transcript.map(\.text) == ["one"])
    #expect(result.records.last == .ended(at: 0.5, byUser: true))
  }

  @Test func forwardsLevelsAndOfflineChanges() async throws {
    let (levels, levelSink) = AsyncStream.makeStream(of: Double.self)
    let (offline, offlineSink) = AsyncStream.makeStream(of: Bool.self)
    let (events, input) = AsyncStream.makeStream(of: TranscriptEvent.self)
    let live = LiveSessionLoop(
      config: .initial, dependencies: base.deps(SilentDecisionProvider()),
      transcriber: OpenTranscriber(stream: events, input: input), levels: levels, offline: offline)
    await live.start()
    levelSink.yield(0.4)
    offlineSink.yield(true)
    var seen: [String] = []
    for await event in live.events() {
      switch event {
      case .speechLevel(let level): seen.append("level \(level)")
      case .offline(let state): seen.append("offline \(state)")
      default: break
      }
      if seen.count == 2 { await live.end() }
    }
    #expect(seen.sorted() == ["level 0.4", "offline true"])
  }
}

/// Stays open until the test ends it, like a microphone would. `stop()` ends the stream at once.
struct OpenTranscriber: Transcriber {
  let stream: AsyncStream<TranscriptEvent>
  let input: AsyncStream<TranscriptEvent>.Continuation
  func events() -> AsyncStream<TranscriptEvent> { stream }
  func stop() async {
    input.yield(.ended)
    input.finish()
  }
}

/// A microphone with an utterance open when End arrives: `stop()` finalises it before `.ended`.
struct FinalisingTranscriber: Transcriber {
  let stream: AsyncStream<TranscriptEvent>
  let input: AsyncStream<TranscriptEvent>.Continuation
  let last: Segment
  func events() -> AsyncStream<TranscriptEvent> { stream }
  func stop() async {
    input.yield(.segment(last))
    input.yield(.speechEnded(at: last.end))
    input.yield(.ended)
    input.finish()
  }
}

/// A transcriber whose `stop()` never ends the stream.
struct StuckTranscriber: Transcriber {
  let stream: AsyncStream<TranscriptEvent>
  func events() -> AsyncStream<TranscriptEvent> { stream }
  func stop() async {}
}

extension AsyncStream<SessionEvent>.Iterator {
  /// Reads up to and including the first event the predicate accepts, or to the end.
  mutating func next(until accept: (SessionEvent) -> Bool) async -> [SessionEvent] {
    var seen: [SessionEvent] = []
    while let event = await next() {
      seen.append(event)
      if accept(event) { break }
    }
    return seen
  }

  mutating func rest() async -> [SessionEvent] {
    await next(until: { _ in false })
  }
}
