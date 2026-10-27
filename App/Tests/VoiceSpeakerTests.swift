import Foundation
import Synchronization
import TestSupport
import Testing

@testable import ooooh

/// The real actor over its player. The scripted transport streams the AudioTests line.mp3 the way
/// bytes land from the Worker; the simulator's engine renders it.
@Suite(.serialized) struct VoiceSpeakerTests {
  let line = "Which part feels least clear, the queue or the sync?"

  /// How each audio stream ended: `cancelled` when the player dropped it.
  final class Endings: Sendable {
    private let reasons = Mutex<[String]>([])

    var all: [String] { reasons.withLock { $0 } }

    func record(_ reason: AsyncThrowingStream<Data, Error>.Continuation.Termination) {
      if case .cancelled = reason {
        reasons.withLock { $0.append("cancelled") }
      } else {
        reasons.withLock { $0.append("finished") }
      }
    }
  }

  /// A speak transport the Worker never answers. Records each line asked for and how each
  /// stream ended.
  final class HangingTransport: Sendable {
    private let lines = Mutex<[String]>([])
    private let endings = Endings()

    var requests: [String] { lines.withLock { $0 } }
    var ended: [String] { endings.all }

    func audio(_ text: String) -> AsyncThrowingStream<Data, Error> {
      lines.withLock { $0.append(text) }
      return AsyncThrowingStream { continuation in
        continuation.onTermination = { reason in self.endings.record(reason) }
      }
    }
  }

  /// Yields line.mp3 1 KiB at a time with a short gap, whatever the text.
  final class ScriptedTransport: Sendable {
    private let chunks: [Data]
    private let endings = Endings()

    var ended: [String] { endings.all }

    init() throws {
      let data = try Bundle.tests.fixture("line.mp3")
      chunks = stride(from: 0, to: data.count, by: 1024).map {
        data[$0..<min($0 + 1024, data.count)]
      }
    }

    func audio(_ text: String) -> AsyncThrowingStream<Data, Error> {
      AsyncThrowingStream { continuation in
        let task = Task {
          for chunk in chunks {
            continuation.yield(chunk)
            try await Task.sleep(for: .milliseconds(20))
          }
          continuation.finish()
        }
        continuation.onTermination = { reason in
          task.cancel()
          self.endings.record(reason)
        }
      }
    }
  }

  @Test func buildsNoAudioEngineUntilItSpeaks() async {
    let speaker = VoiceSpeaker { _ in AsyncThrowingStream { $0.finish() } }
    #expect(await speaker.hasEngine == false)
  }

  @Test func aLinePlaysThroughAndReportsBothEnds() async throws {
    let transport = try ScriptedTransport()
    let speaker = VoiceSpeaker(audio: transport.audio)
    let clock = ContinuousClock()
    var events: [SpeechEvent] = []
    let took = await clock.measure {
      for await event in speaker.speak(text: line) { events.append(event) }
    }
    print("the line played in \(took)")
    #expect(ProcessInfo.processInfo.environment["OOOOH_SILENT_TESTS"] == "1")
    #expect(events == [.started, .finished])
    #expect(transport.ended == ["finished"])
    #expect(await speaker.hasEngine)
  }

  @Test func stopCutsTheLineAndDropsTheRestOfTheStream() async throws {
    let transport = try ScriptedTransport()
    let speaker = VoiceSpeaker(audio: transport.audio)
    var events = speaker.speak(text: line).makeAsyncIterator()
    #expect(await events.next() == .started)
    let stoppedAt = ContinuousClock.now
    await speaker.stop()
    #expect(await events.next() == .finished)
    #expect(await events.next() == nil)
    print("stop ended the line in \(ContinuousClock.now - stoppedAt)")
    await wait { !transport.ended.isEmpty }
    #expect(transport.ended == ["cancelled"])
  }

  @Test func aNewLineCutsTheOneBeforeIt() async throws {
    let transport = try ScriptedTransport()
    let speaker = VoiceSpeaker(audio: transport.audio)
    var first = speaker.speak(text: "first").makeAsyncIterator()
    #expect(await first.next() == .started)
    let second = Task {
      var events: [SpeechEvent] = []
      for await event in speaker.speak(text: "second") { events.append(event) }
      return events
    }
    #expect(await first.next() == .finished)
    #expect(await first.next() == nil)
    #expect(await second.value == [.started, .finished])
    await wait { transport.ended.count == 2 }
    #expect(transport.ended == ["cancelled", "finished"])
  }

  @Test func stopWhileTheBytesNeverComeCancelsTheRequestAndEndsTheLine() async {
    let transport = HangingTransport()
    let speaker = VoiceSpeaker(audio: transport.audio)
    let line = Task {
      var events: [SpeechEvent] = []
      for await event in speaker.speak(text: "Which part feels least clear?") {
        events.append(event)
      }
      return events
    }
    await wait { transport.requests == ["Which part feels least clear?"] }
    await speaker.stop()
    let events = await line.value
    #expect(events == [] || events == [.finished])
    await wait { !transport.ended.isEmpty }
    #expect(transport.ended == ["cancelled"])
  }

  @Test func droppingTheLineCancelsTheRequest() async {
    let transport = HangingTransport()
    let speaker = VoiceSpeaker(audio: transport.audio)
    let line = Task {
      for await _ in speaker.speak(text: "Which part feels least clear?") {}
    }
    await wait { transport.requests.count == 1 }
    line.cancel()
    await line.value
    await wait { !transport.ended.isEmpty }
    #expect(transport.ended == ["cancelled"])
  }
}
