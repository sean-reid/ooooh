#if canImport(UIKit)
  import Foundation
  import Synchronization
  import Testing

  @testable import Audio

  /// Needs the simulator: AVAudioEngine has to render for the completion callbacks to fire.
  @Suite(.serialized, .timeLimit(.minutes(1))) struct PromptSpeakerTests {
    let text = "Which part feels least clear, the queue or the sync?"

    /// Yields the fixture 1 KiB at a time with a short gap, the way bytes land from the Worker.
    func network(firstByte: @escaping @Sendable (Date) -> Void) throws -> AsyncThrowingStream<
      Data, Error
    > {
      let chunks = Fixture.chunks(try Fixture.line(), size: 1024)
      return AsyncThrowingStream { continuation in
        let task = Task {
          for (i, chunk) in chunks.enumerated() {
            if i == 0 { firstByte(Date()) }
            continuation.yield(chunk)
            try await Task.sleep(for: .milliseconds(20))
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    }

    @Test func startsWithin300msOfTheFirstByteAndReportsBothEnds() async throws {
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
        case .finished(let finishedAt) = try #require(events.last)
      else {
        Issue.record("expected started then finished, got \(events)")
        return
      }
      let first = try #require(firstByte.withLock { $0 })
      let lead = startedAt.timeIntervalSince(first)
      let played = finishedAt.timeIntervalSince(startedAt)
      print("playback started \(Int(lead * 1000)) ms after the first byte, played \(played) s")
      #expect(spoken == text)
      #expect(events.count == 2)
      #expect(lead < 0.3)
      #expect(played > 2.5 && played < 6)
      #expect(await speaker.text == nil)
    }

    @Test func stopHaltsAtOnceAndDropsTheRest() async throws {
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
      var finishedAt = Date.distantFuture
      while let event = await events.next() {
        if case .finished(let at) = event {
          finishedAt = at
          break
        }
      }
      print("speak returned \(Int(returned * 1000)) ms after stop")
      #expect(returned < 0.1)
      #expect(abs(finishedAt.timeIntervalSince(stoppedAt)) < 0.1)
      #expect(await speaker.text == nil)
    }
  }
#endif
