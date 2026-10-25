import CoreMedia
import Foundation
import Testing

@testable import Transcription

@Suite struct SegmentTimingTests {
  @Test func convertsMediaTimeToSecondsFromSessionStart() {
    let range = CMTimeRange(
      start: CMTime(value: 96000, timescale: 48000),
      duration: CMTime(value: 24000, timescale: 48000))
    let segment = Segment(text: "hi", range: range, isFinal: true)
    #expect(segment.start == 2.0)
    #expect(segment.end == 2.5)
  }

  @Test func clampsInvalidAndNegativeTimes() {
    let open = CMTimeRange(start: CMTime(value: 3, timescale: 1), duration: .invalid)
    let segment = Segment(text: "", range: open, isFinal: false)
    #expect(segment.start == 3)
    #expect(segment.end == 3)

    let negative = CMTimeRange(
      start: CMTime(value: -5, timescale: 10), duration: CMTime(value: 10, timescale: 10))
    let clamped = Segment(text: "", range: negative, isFinal: false)
    #expect(clamped.start == 0)
    #expect(clamped.end == 0.5)
  }
}

@Suite struct VoiceActivityTests {
  @Test func opensOnFirstResultAndClosesOnFinal() {
    var activity = VoiceActivity()
    let first = Segment(text: "so", start: 0.5, end: 1.0, isFinal: false)
    let second = Segment(text: "so I", start: 0.5, end: 1.4, isFinal: false)
    let final = Segment(text: "So I think", start: 0.5, end: 1.5, isFinal: true)
    #expect(activity.events(for: first) == [.speechStarted(at: 0.5), .segment(first)])
    #expect(activity.events(for: second) == [.segment(second)])
    #expect(activity.events(for: final) == [.segment(final), .speechEnded(at: 1.5)])
    #expect(activity.close().isEmpty)
  }

  @Test func closeEndsAnOpenUtteranceAtItsLastKnownEnd() {
    var activity = VoiceActivity()
    _ = activity.events(for: Segment(text: "and", start: 2, end: 2.3, isFinal: false))
    _ = activity.events(for: Segment(text: "and then", start: 2, end: 2.9, isFinal: false))
    #expect(activity.close() == [.speechEnded(at: 2.9)])
  }
}
