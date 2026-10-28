import AVFAudio
import Foundation
import TestSupport
import Testing

@testable import Transcription

@Suite struct FileRecognitionTests {
  typealias FakeRecognizer = SpeechRecognizerTranscriberTests.FakeRecognizer

  func word(_ text: String, _ timestamp: TimeInterval, _ duration: TimeInterval = 0.5)
    -> RecognizedWord
  {
    RecognizedWord(text: text, timestamp: timestamp, duration: duration)
  }

  /// A 16 kHz mono WAV of `seconds` of silence, the format the voice step writes.
  func silentWAV(seconds: Double) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("file-recognition-\(UUID().uuidString).wav")
    let format = AVAudioFormat(
      commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    let file = try AVAudioFile(
      forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
    let frames = AVAudioFrameCount(seconds * 16000)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    try file.write(from: buffer)
    return url
  }

  /// At speed 1 the feed parks on the clock after every 4096-frame buffer, so one advance feeds
  /// that much audio and parks on the first buffer past it.
  @Test func feedsTheFileThroughRotatingRequestsAndKeepsTheClock() async throws {
    let url = try silentWAV(seconds: 60)
    defer { try? FileManager.default.removeItem(at: url) }
    let recognizer = FakeRecognizer()
    let clock = TestClock()
    let run = Task {
      try await SpeechRecognizerTranscriber.transcribe(
        file: url, recognizer: recognizer, locale: Locale(identifier: "en_US"), onDevice: true,
        speed: 1, clock: OffsetClock(clock))
    }
    await wait(for: "the feed to park on the clock") { clock.sleeping == 1 }
    #expect(recognizer.requests == 1)

    // The feed rotates at the first buffer boundary past 50 s, 196 buffers in.
    clock.advance(by: .seconds(55))
    await recognizer.waitForRequests(2)
    // Results for an ended request schedule no pause timer.
    await recognizer.report(
      RecognitionResult(words: [word("hello", 1.0)], isFinal: false), request: 0)
    await recognizer.report(
      RecognitionResult(words: [word("hello", 1.0), word("there", 3.0)], isFinal: true),
      request: 0)
    await recognizer.report(
      RecognitionResult(words: [word("next", 1.0)], isFinal: true), request: 1)
    await recognizer.waitForRequests(3)

    // Stop waits on the clock for the third request's final, which never comes, up to 1.5 s.
    clock.advance(by: .seconds(10))
    await wait(for: "stop to park on the clock") { clock.sleeping == 1 }
    clock.advance(by: .seconds(1.5))
    let segments = try await run.value

    try #require(segments.count == 3)
    #expect(segments.map(\.text) == ["hello", "there", "next"])
    #expect(segments.map(\.isFinal) == [true, true, true])
    #expect(segments[0].start == 1.0 && segments[0].end == 1.5)
    #expect(segments[1].start == 3.0 && segments[1].end == 3.5)
    #expect(abs(segments[2].start - 51.176) < 1e-6)
    #expect(abs(segments[2].end - 51.676) < 1e-6)
    #expect(recognizer.requests == 3)
    #expect(recognizer.cancelled == 1)
  }

  @Test func refusesWhenTheRecognizerIsUnavailable() async throws {
    let url = try silentWAV(seconds: 1)
    defer { try? FileManager.default.removeItem(at: url) }
    await #expect(throws: SpeechRecognizerError.unavailable) {
      try await SpeechRecognizerTranscriber.transcribe(
        file: url, recognizer: FakeRecognizer(isAvailable: false),
        locale: Locale(identifier: "en_US"), onDevice: true, speed: .infinity,
        clock: OffsetClock(TestClock()))
    }
  }
}
