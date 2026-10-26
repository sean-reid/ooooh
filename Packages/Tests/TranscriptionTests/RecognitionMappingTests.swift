import AVFAudio
import Foundation
import Testing

@testable import Transcription

/// Word times are quarter seconds, so every sum is exact in a Double.
@Suite struct UtteranceSplitterTests {
  func word(_ text: String, _ timestamp: TimeInterval, _ duration: TimeInterval = 0.5)
    -> RecognizedWord
  {
    RecognizedWord(text: text, timestamp: timestamp, duration: duration)
  }

  @Test func aGrowingPartialIsOneVolatileSegmentUntilAPauseSplitsIt() {
    var splitter = UtteranceSplitter(offset: 0, pause: 1)
    let first = splitter.segments(
      for: RecognitionResult(words: [word("So", 0.5)], isFinal: false), at: 1)
    #expect(first == [Segment(text: "So", start: 0.5, end: 1.0, isFinal: false)])

    let second = splitter.segments(
      for: RecognitionResult(words: [word("So", 0.5), word("the", 1.0)], isFinal: false), at: 1.5)
    #expect(second == [Segment(text: "So the", start: 0.5, end: 1.5, isFinal: false)])

    let third = splitter.segments(
      for: RecognitionResult(
        words: [word("So", 0.5), word("the", 1.0), word("pricing", 3.0)], isFinal: false),
      at: 3.5)
    #expect(
      third == [
        Segment(text: "So the", start: 0.5, end: 1.5, isFinal: true),
        Segment(text: "pricing", start: 3.0, end: 3.5, isFinal: false),
      ])
    #expect(splitter.settledWords == 2)
  }

  @Test func aFinalResultSettlesEveryUtterance() {
    var splitter = UtteranceSplitter(offset: 0, pause: 1)
    _ = splitter.segments(
      for: RecognitionResult(words: [word("So", 0.5), word("the", 1.0)], isFinal: false), at: 1.5)
    let final = splitter.segments(
      for: RecognitionResult(
        words: [word("So", 0.5), word("the", 1.0), word("pricing", 3.0), word("page", 3.5)],
        isFinal: true),
      at: 4)
    #expect(
      final == [
        Segment(text: "So the", start: 0.5, end: 1.5, isFinal: true),
        Segment(text: "pricing page", start: 3.0, end: 4.0, isFinal: true),
      ])
    #expect(splitter.flush(at: 5) == nil)
  }

  @Test func theOffsetMovesWordTimesOntoTheSessionClock() {
    var splitter = UtteranceSplitter(offset: 50, pause: 1)
    let segments = splitter.segments(
      for: RecognitionResult(words: [word("again", 0.25)], isFinal: true), at: 51)
    #expect(segments == [Segment(text: "again", start: 50.25, end: 50.75, isFinal: true)])
  }

  @Test func flushFinalizesTheOpenUtterance() {
    var splitter = UtteranceSplitter(offset: 0, pause: 1)
    _ = splitter.segments(
      for: RecognitionResult(words: [word("needs", 6.0), word("a", 6.5)], isFinal: false), at: 7)
    #expect(splitter.flush(at: 8) == Segment(text: "needs a", start: 6.0, end: 7.0, isFinal: true))
    #expect(splitter.flush(at: 9) == nil)

    let next = splitter.segments(
      for: RecognitionResult(
        words: [word("needs", 6.0), word("a", 6.5), word("rewrite", 8.5)], isFinal: false), at: 9)
    #expect(next == [Segment(text: "rewrite", start: 8.5, end: 9.0, isFinal: false)])
  }

  @Test func untimedWordsTakeTheAudioClock() {
    var splitter = UtteranceSplitter(offset: 10, pause: 1)
    let untimed = { (words: [String]) in
      RecognitionResult(
        words: words.map { RecognizedWord(text: $0, timestamp: 0, duration: 0) }, isFinal: false)
    }
    #expect(
      splitter.segments(for: untimed(["I"]), at: 11)
        == [Segment(text: "I", start: 11, end: 11, isFinal: false)])
    #expect(
      splitter.segments(for: untimed(["I", "think"]), at: 11.5)
        == [Segment(text: "I think", start: 11, end: 11.5, isFinal: false)])
    #expect(splitter.flush(at: 13) == Segment(text: "I think", start: 11, end: 13, isFinal: true))
    #expect(
      splitter.segments(for: untimed(["I", "think", "so"]), at: 14)
        == [Segment(text: "so", start: 14, end: 14, isFinal: false)])
  }

  @Test func aShorterRevisionEmitsNothing() {
    var splitter = UtteranceSplitter(offset: 0, pause: 1)
    _ = splitter.segments(
      for: RecognitionResult(words: [word("So", 0.5), word("the", 1.0)], isFinal: false), at: 1.5)
    _ = splitter.flush(at: 3)
    #expect(
      splitter.segments(for: RecognitionResult(words: [word("So", 0.5)], isFinal: false), at: 3.5)
        .isEmpty)
    #expect(splitter.segments(for: RecognitionResult(words: [], isFinal: true), at: 4).isEmpty)
  }
}

@Suite struct RequestFeedTests {
  final class Request: AudioAppending {
    var frames: AVAudioFrameCount = 0
    func append(_ buffer: AVAudioPCMBuffer) { frames += buffer.frameLength }
  }

  func buffer(seconds: Double) throws -> AVAudioPCMBuffer {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
    let frames = AVAudioFrameCount(seconds * 16000)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    return buffer
  }

  @Test func feedsTheLiveRequestAndReportsTheLimitOnce() throws {
    let feed = RequestFeed<Request>(limit: 1)
    let first = Request()
    #expect(feed.swap(in: first).start == 0)
    #expect(feed.append(try buffer(seconds: 0.5)) == false)
    #expect(feed.append(try buffer(seconds: 0.5)) == true)
    #expect(feed.append(try buffer(seconds: 0.5)) == false)
    #expect(first.frames == 24000)
    #expect(feed.audioTime == 1.5)
    #expect(feed.elapsedInRequest == 1.5)

    let second = Request()
    let swapped = feed.swap(in: second)
    #expect(swapped.previous === first)
    #expect(swapped.start == 1.5)
    #expect(feed.elapsedInRequest == 0)
    #expect(feed.append(try buffer(seconds: 0.5)) == false)
    #expect(second.frames == 8000)
    #expect(first.frames == 24000)
  }

  @Test func audioWithNoLiveRequestStillMovesTheClock() throws {
    let feed = RequestFeed<Request>(limit: 1)
    #expect(feed.append(try buffer(seconds: 2)) == false)
    #expect(feed.audioTime == 2)
    #expect(feed.swap(in: Request()).start == 2)
  }
}
