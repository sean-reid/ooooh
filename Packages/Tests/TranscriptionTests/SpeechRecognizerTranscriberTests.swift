import Foundation
import Speech
import TestSupport
import Testing

@testable import Transcription

/// Word times are quarter seconds, so every sum is exact in a Double.
@Suite struct SpeechRecognizerTranscriberTests {
  typealias Handler = @Sendable (RecognitionResult?, (any Error)?) -> Void

  /// Keeps every request's handler so a test can play results into it. The actor starts the next
  /// request on its own turn, so `report` waits for the request to exist.
  final class FakeRecognizer: SpeechRecognizing, @unchecked Sendable {
    let isAvailable: Bool
    private let lock = NSLock()
    private var handlers: [Handler] = []
    private(set) var cancelled = 0

    init(isAvailable: Bool = true) { self.isAvailable = isAvailable }

    var requests: Int { lock.withLock { handlers.count } }

    func recognize(_ request: SFSpeechAudioBufferRecognitionRequest, handler: @escaping Handler) {
      lock.withLock { handlers.append(handler) }
    }

    func cancelAll() { lock.withLock { cancelled += 1 } }

    func waitForRequests(_ count: Int) async {
      await wait(for: "request \(count)") { requests >= count }
    }

    func report(_ result: RecognitionResult?, error: (any Error)? = nil, request: Int) async {
      await waitForRequests(request + 1)
      let handler = lock.withLock { handlers[request] }
      handler(result, error)
    }
  }

  struct Failed: Error {}

  func word(_ text: String, _ timestamp: TimeInterval, _ duration: TimeInterval = 0.5)
    -> RecognizedWord
  {
    RecognizedWord(text: text, timestamp: timestamp, duration: duration)
  }

  func collect(_ stream: AsyncStream<TranscriptEvent>, count: Int) async -> [TranscriptEvent] {
    var events: [TranscriptEvent] = []
    for await event in stream {
      events.append(event)
      if events.count == count { break }
    }
    return events
  }

  @Test func refusesWhenTheRecognizerIsNotAvailable() async {
    let transcriber = SpeechRecognizerTranscriber(
      recognizer: FakeRecognizer(isAvailable: false), locale: Locale(identifier: "en_US"))
    await #expect(throws: SpeechRecognizerError.unavailable) {
      try await transcriber.start()
    }
    #expect(transcriber.engine == .speechRecognizer)
  }

  @Test func downloadsNoModel() async {
    let transcriber = SpeechRecognizerTranscriber(
      recognizer: FakeRecognizer(), locale: Locale(identifier: "en_US"))
    var fractions: [Double] = []
    for await fraction in transcriber.downloadProgress() {
      fractions.append(fraction)
    }
    #expect(fractions.isEmpty)
  }

  @Test func mapsPartialsAndFinalsToSegmentsWithSpeechBoundaries() async throws {
    let recognizer = FakeRecognizer()
    let transcriber = SpeechRecognizerTranscriber(
      recognizer: recognizer, locale: Locale(identifier: "en_US"), pause: 1)
    try await transcriber.beginRecognition()
    #expect(recognizer.requests == 1)

    await recognizer.report(RecognitionResult(words: [word("So", 0.5)], isFinal: false), request: 0)
    await recognizer.report(
      RecognitionResult(words: [word("So", 0.5), word("the", 1.0)], isFinal: false), request: 0)
    await recognizer.report(
      RecognitionResult(
        words: [word("So", 0.5), word("the", 1.0), word("pricing", 3.0)], isFinal: false),
      request: 0)
    let events = await collect(transcriber.events(), count: 6)
    #expect(
      events == [
        .speechStarted(at: 0.5),
        .segment(Segment(text: "So", start: 0.5, end: 1.0, isFinal: false)),
        .segment(Segment(text: "So the", start: 0.5, end: 1.5, isFinal: false)),
        .segment(Segment(text: "So the", start: 0.5, end: 1.5, isFinal: true)),
        .speechEnded(at: 1.5),
        .speechStarted(at: 3.0),
      ])
    await transcriber.stop()
  }

  @Test func aFinalResultStartsTheNextRequestAndKeepsTheClock() async throws {
    let recognizer = FakeRecognizer()
    let transcriber = SpeechRecognizerTranscriber(
      recognizer: recognizer, locale: Locale(identifier: "en_US"), pause: 60)
    try await transcriber.beginRecognition()
    await recognizer.report(
      RecognitionResult(words: [word("Done", 0.25)], isFinal: true), request: 0)
    let first = await collect(transcriber.events(), count: 3)
    #expect(
      first == [
        .speechStarted(at: 0.25),
        .segment(Segment(text: "Done", start: 0.25, end: 0.75, isFinal: true)),
        .speechEnded(at: 0.75),
      ])

    await recognizer.report(
      RecognitionResult(words: [word("Next", 0.25)], isFinal: true), request: 1)
    let second = await collect(transcriber.events(), count: 3)
    #expect(second[1] == .segment(Segment(text: "Next", start: 0.25, end: 0.75, isFinal: true)))
    await recognizer.waitForRequests(3)
    #expect(recognizer.requests == 3)
    await transcriber.stop()
  }

  @Test func anErrorAfterSpeechRestartsAndThreeSilentFailuresEndTheStream() async throws {
    let recognizer = FakeRecognizer()
    let transcriber = SpeechRecognizerTranscriber(
      recognizer: recognizer, locale: Locale(identifier: "en_US"), pause: 60)
    try await transcriber.beginRecognition()
    await recognizer.report(RecognitionResult(words: [word("Hi", 0.5)], isFinal: false), request: 0)
    await recognizer.report(nil, error: Failed(), request: 0)
    let flushed = await collect(transcriber.events(), count: 4)
    #expect(flushed[2] == .segment(Segment(text: "Hi", start: 0.5, end: 1.0, isFinal: true)))
    #expect(flushed[3] == .speechEnded(at: 1.0))

    await recognizer.report(nil, error: Failed(), request: 1)
    await recognizer.report(nil, error: Failed(), request: 2)
    await recognizer.report(nil, error: Failed(), request: 3)
    let rest = await collect(transcriber.events(), count: 1)
    #expect(rest == [.ended])
    #expect(recognizer.requests == 4)
    #expect(recognizer.cancelled == 1)
  }

  @Test func silenceFlushesTheOpenUtterance() async throws {
    let recognizer = FakeRecognizer()
    let transcriber = SpeechRecognizerTranscriber(
      recognizer: recognizer, locale: Locale(identifier: "en_US"), pause: 0.05)
    try await transcriber.beginRecognition()
    await recognizer.report(
      RecognitionResult(words: [word("Hmm", 1.0)], isFinal: false), request: 0)
    let events = await collect(transcriber.events(), count: 4)
    #expect(events[2] == .segment(Segment(text: "Hmm", start: 1.0, end: 1.5, isFinal: true)))
    #expect(events[3] == .speechEnded(at: 1.5))
    #expect(recognizer.requests == 1)
    await transcriber.stop()
  }
}
