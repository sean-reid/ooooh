import AVFAudio
import Foundation
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

  @Test func feedsTheFileThroughRotatingRequestsAndKeepsTheClock() async throws {
    let url = try silentWAV(seconds: 60)
    defer { try? FileManager.default.removeItem(at: url) }
    let recognizer = FakeRecognizer()
    let run = Task {
      try await SpeechRecognizerTranscriber.transcribe(
        file: url, recognizer: recognizer, locale: Locale(identifier: "en_US"), onDevice: true,
        speed: 30)
    }
    await recognizer.report(
      RecognitionResult(words: [word("hello", 1.0)], isFinal: false), request: 0)
    // The feed rotates at 50 s of audio, so a second request appears before the file ends.
    await recognizer.waitForRequests(2)
    await recognizer.report(
      RecognitionResult(words: [word("hello", 1.0), word("there", 3.0)], isFinal: true),
      request: 0)
    await recognizer.report(
      RecognitionResult(words: [word("next", 1.0)], isFinal: true), request: 1)
    let segments = try await run.value
    // "there" sits a full pause after "hello", so the word times split them whether or not the
    // pause timer fires first; the second request starts at the first buffer boundary past 50 s,
    // 196 buffers of 4096 frames.
    try #require(segments.count == 3)
    #expect(segments.map(\.text) == ["hello", "there", "next"])
    #expect(segments.map(\.isFinal) == [true, true, true])
    #expect(segments[0].start == 1.0 && segments[0].end == 1.5)
    #expect(segments[1].start == 3.0 && segments[1].end == 3.5)
    #expect(abs(segments[2].start - 51.176) < 1e-6)
    #expect(abs(segments[2].end - 51.676) < 1e-6)
    // The final on the second request starts a third, the way a live final does.
    #expect(recognizer.requests == 3)
    #expect(recognizer.cancelled >= 1)
  }

  @Test func refusesWhenTheRecognizerIsUnavailable() async throws {
    let url = try silentWAV(seconds: 1)
    defer { try? FileManager.default.removeItem(at: url) }
    await #expect(throws: SpeechRecognizerError.unavailable) {
      try await SpeechRecognizerTranscriber.transcribe(
        file: url, recognizer: FakeRecognizer(isAvailable: false),
        locale: Locale(identifier: "en_US"), onDevice: true, speed: .infinity)
    }
  }
}
