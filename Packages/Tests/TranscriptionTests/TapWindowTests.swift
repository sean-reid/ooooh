import Foundation
import Testing

@testable import Transcription

/// Buffers are 12000 frames at 48 kHz, a quarter second, so every audio time is exact in a Double.
@Suite struct TapWindowTests {
  @Test func reportsTheFirstBufferThenOneWindowPerInterval() {
    var window = TapWindow(interval: 5)
    #expect(
      window.record(frames: 12000, sampleRate: 48000, rms: 0.01)
        == .first(frames: 12000, rms: 0.01))
    for _ in 1..<19 {
      #expect(window.record(frames: 12000, sampleRate: 48000, rms: 0.02) == nil)
    }
    let first = window.record(frames: 12000, sampleRate: 48000, rms: 0.3)
    #expect(first == .window(buffers: 20, peakRMS: 0.3, audioTime: 5))

    for _ in 0..<19 {
      #expect(window.record(frames: 12000, sampleRate: 48000, rms: 0) == nil)
    }
    let second = window.record(frames: 12000, sampleRate: 48000, rms: 0)
    #expect(second == .window(buffers: 20, peakRMS: 0, audioTime: 10))
  }

  @Test func aLongBufferClosesEveryWindowItCrosses() {
    var window = TapWindow(interval: 5)
    _ = window.record(frames: 24000, sampleRate: 48000, rms: 0)
    let report = window.record(frames: 48000 * 12, sampleRate: 48000, rms: 0.5)
    #expect(report == .window(buffers: 2, peakRMS: 0.5, audioTime: 12.5))
    for _ in 0..<4 {
      #expect(window.record(frames: 24000, sampleRate: 48000, rms: 0) == nil)
    }
    #expect(
      window.record(frames: 24000, sampleRate: 48000, rms: 0)
        == .window(buffers: 5, peakRMS: 0, audioTime: 15))
  }

  @Test func linesStayShortAndParseable() {
    #expect(
      TapWindow.Report.first(frames: 4096, rms: 0.00012).line
        == "tap first buffer frames=4096 rms=0.0001")
    #expect(
      TapWindow.Report.window(buffers: 58, peakRMS: 0.25, audioTime: 5.03).line
        == "tap window buffers=58 peakRms=0.2500 audioTime=5")
  }

  @Test func latencyRoundsDownToWholeMilliseconds() {
    #expect(Duration.milliseconds(1234).wholeMilliseconds == 1234)
    #expect((Duration.seconds(2) + .microseconds(1999)).wholeMilliseconds == 2001)
  }
}
