#if canImport(UIKit)
  import AVFAudio
  import Foundation
  import Synchronization
  import TestSupport
  import Testing

  @testable import Audio

  /// Needs the simulator: AVAudioEngine has to render for the completion callbacks to fire.
  /// Durations are read from the player's own frame clock; the two wall-clock latencies are printed, not gated.
  @Suite(.serialized, .timeLimit(.minutes(1))) struct PromptSpeakerTests {
    let text = "Which part feels least clear, the queue or the sync?"
    /// The completion callback lands a render cycle or two past the last frame; this is four cycles.
    let slack: AVAudioFramePosition = 2048
    /// The completion callback lands late on a loaded runner; a second of audio is the ceiling.
    let lateness: AVAudioFramePosition = 48_000

    /// Yields the fixture 1 KiB at a time with a short gap, the way bytes land from the Worker.
    /// `ended` is told how the stream ended: `cancelled` when the player dropped it. With
    /// `holding`, the stream stops before that chunk until `release` yields.
    func network(
      firstByte: @escaping @Sendable (Date) -> Void, ended: Ended? = nil,
      holding held: Int = .max, until release: AsyncStream<Void>? = nil
    ) throws -> AsyncThrowingStream<Data, Error> {
      let chunks = Fixture.chunks(try Fixture.line(), size: 1024)
      return AsyncThrowingStream { continuation in
        let task = Task {
          for (i, chunk) in chunks.enumerated() {
            if i == 0 { firstByte(Date()) }
            if i == held, let release {
              for await _ in release { break }
            }
            continuation.yield(chunk)
            try await Task.sleep(for: .milliseconds(20))
          }
          continuation.finish()
        }
        continuation.onTermination = { reason in
          task.cancel()
          ended?.record(reason)
        }
      }
    }

    /// A request the Worker never answers. `ended` is told how the stream ended.
    func silence(ended: Ended) -> AsyncThrowingStream<Data, Error> {
      AsyncThrowingStream { continuation in
        continuation.onTermination = { reason in ended.record(reason) }
      }
    }

    final class Ended: Sendable {
      private let reasons = Mutex<[String]>([])

      func record(_ reason: AsyncThrowingStream<Data, Error>.Continuation.Termination) {
        if case .cancelled = reason {
          reasons.withLock { $0.append("cancelled") }
        } else {
          reasons.withLock { $0.append("finished") }
        }
      }

      var all: [String] { reasons.withLock { $0 } }
    }

    @Test func buildsNoEngineUntilALineIsSpoken() async {
      let speaker = PromptSpeaker()
      #expect(await speaker.hasEngine == false)
      #expect(await speaker.rendered == nil)
    }

    @Test func playsEveryFrameAndReportsBothEnds() async throws {
      let speaker = PromptSpeaker()
      let collected = Task {
        var events: [PromptSpeaker.Event] = []
        for await event in speaker.events {
          events.append(event)
          if case .finished = event { break }
        }
        return events
      }
      let firstByte = Mutex<Date?>(nil)
      let audio = try network { at in firstByte.withLock { $0 = at } }
      try await speaker.speak(text, audio: audio)
      let events = await collected.value

      guard case .started(let spoken, let startedAt) = try #require(events.first),
        case .finished(let finishedAt, let rendered) = try #require(events.last)
      else {
        Issue.record("expected started then finished, got \(events)")
        return
      }
      let frames = try Fixture.frames(chunked: 1024)
      let first = try #require(firstByte.withLock { $0 })
      let lead = startedAt.timeIntervalSince(first)
      let played = finishedAt.timeIntervalSince(startedAt)
      let gain = await speaker.lineGainDB
      print(
        "playback started \(Int(lead * 1000)) ms after the first byte, played \(played) s,"
          + " rendered \(rendered) of \(frames) frames, line gain \(gain) dB")
      #expect(spoken == text)
      #expect(events.count == 2)
      #expect(lead > 0)
      #expect(finishedAt > startedAt)
      #expect(rendered >= frames - slack)
      #expect(rendered <= frames + lateness)
      #expect(await speaker.rendered == nil)
      #expect(await speaker.text == nil)
      #expect(await speaker.hasEngine)
      #expect(gain > 3 && gain < 5)
    }

    @Test func stopCutsPlaybackAndDropsTheRest() async throws {
      let speaker = PromptSpeaker()
      var events = speaker.events.makeAsyncIterator()
      let audio = try network { _ in }
      let speaking = Task { try await speaker.speak(text, audio: audio) }
      while let event = await events.next() {
        if case .started = event { break }
      }
      try await Task.sleep(for: .milliseconds(300))
      #expect(await speaker.text == text)
      let stoppedAt = Date()
      await speaker.stop()
      try await speaking.value
      let returned = Date().timeIntervalSince(stoppedAt)
      var finishedAt = Date.distantPast
      var cut: AVAudioFramePosition = -1
      while let event = await events.next() {
        if case .finished(let at, let rendered) = event {
          finishedAt = at
          cut = rendered
          break
        }
      }
      let frames = try Fixture.frames(chunked: 1024)
      print(
        "speak returned \(Int(returned * 1000)) ms after stop, cut at \(cut) of \(frames) frames")
      #expect(returned > 0)
      #expect(finishedAt >= stoppedAt)
      #expect(cut > 0)
      #expect(cut < frames - slack)
      try await Task.sleep(for: .milliseconds(100))
      #expect(await speaker.rendered == nil)
      #expect(await speaker.text == nil)
    }

    @Test func stopWhileTheBytesNeverComeCancelsTheRequest() async throws {
      let speaker = PromptSpeaker()
      var events = speaker.events.makeAsyncIterator()
      let ended = Ended()
      let speaking = Task { try await speaker.speak(text, audio: silence(ended: ended)) }
      await wait { await speaker.text == text }
      #expect(ended.all.isEmpty)
      await speaker.stop()
      try await speaking.value
      await wait { !ended.all.isEmpty }
      #expect(ended.all == ["cancelled"])
      #expect(await speaker.text == nil)
      #expect(await speaker.rendered == nil)
      guard case .finished = await events.next() else {
        Issue.record("expected finished with no started")
        return
      }
    }

    @Test func cancellingTheCallerCancelsTheRequest() async throws {
      let speaker = PromptSpeaker()
      var events = speaker.events.makeAsyncIterator()
      let ended = Ended()
      let speaking = Task { try await speaker.speak(text, audio: silence(ended: ended)) }
      await wait { await speaker.text == text }
      speaking.cancel()
      try await speaking.value
      await wait { !ended.all.isEmpty }
      #expect(ended.all == ["cancelled"])
      #expect(await speaker.text == nil)
      guard case .finished = await events.next() else {
        Issue.record("expected finished with no started")
        return
      }
    }

    @Test func stopDuringTheFirstChunksLeavesNothingDangling() async throws {
      let speaker = PromptSpeaker()
      var events = speaker.events.makeAsyncIterator()
      let ended = Ended()
      let (release, releasing) = AsyncStream.makeStream(of: Void.self)
      let audio = try network(firstByte: { _ in }, ended: ended, holding: 2, until: release)
      let speaking = Task { try await speaker.speak(text, audio: audio) }
      await wait { await speaker.text == text }
      await speaker.stop()
      try await speaking.value
      releasing.finish()
      await wait { !ended.all.isEmpty }
      #expect(ended.all == ["cancelled"])
      #expect(await speaker.text == nil)
      #expect(await speaker.rendered == nil)
      var first = await events.next()
      if case .started = first { first = await events.next() }
      guard case .finished = first else {
        Issue.record(
          "expected finished, or started then finished, got \(String(describing: first))")
        return
      }
    }

    @Test func renderedFollowsThePlayerClock() async throws {
      let speaker = PromptSpeaker()
      #expect(await speaker.rendered == nil)
      var events = speaker.events.makeAsyncIterator()
      let audio = try network { _ in }
      let speaking = Task { try await speaker.speak(text, audio: audio) }
      while let event = await events.next() {
        if case .started = event { break }
      }
      try await Task.sleep(for: .milliseconds(100))
      let early = try #require(await speaker.rendered)
      try await Task.sleep(for: .milliseconds(100))
      let later = try #require(await speaker.rendered)
      await speaker.stop()
      try await speaking.value
      print("player clock read \(early) then \(later) frames")
      #expect(early >= 0)
      #expect(later > early)
      #expect(await speaker.rendered == nil)
    }
  }
#endif
