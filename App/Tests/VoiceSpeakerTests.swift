import Foundation
import Synchronization
import Testing

@testable import ooooh

@Suite struct VoiceSpeakerTests {
  /// A speak transport the Worker never answers. Records each line asked for and how each
  /// stream ended: `cancelled` when the player dropped it.
  final class HangingTransport: Sendable {
    private let lines = Mutex<[String]>([])
    private let endings = Mutex<[String]>([])

    var requests: [String] { lines.withLock { $0 } }
    var ended: [String] { endings.withLock { $0 } }

    func audio(_ text: String) -> AsyncThrowingStream<Data, Error> {
      lines.withLock { $0.append(text) }
      return AsyncThrowingStream { continuation in
        continuation.onTermination = { reason in self.record(reason) }
      }
    }

    private func record(_ reason: AsyncThrowingStream<Data, Error>.Continuation.Termination) {
      if case .cancelled = reason {
        endings.withLock { $0.append("cancelled") }
      } else {
        endings.withLock { $0.append("finished") }
      }
    }
  }

  @Test func buildsNoAudioEngineUntilItSpeaks() async {
    let speaker = VoiceSpeaker { _ in AsyncThrowingStream { $0.finish() } }
    #expect(await speaker.hasEngine == false)
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
