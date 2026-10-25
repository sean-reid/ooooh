import AVFAudio
import Foundation
import Testing

@testable import Transcription

@Suite struct FixtureRecorderTests {
  let directory = FileManager.default.temporaryDirectory.appending(
    path: "ooooh-fixtures-\(UUID().uuidString)")

  @Test func keepsFinalsAndReplaysThemThroughFixtureTranscriber() async throws {
    let recorder = try FixtureRecorder(directory: directory)
    let first = Segment(text: "So the pricing page", start: 0.8, end: 2.1, isFinal: true)
    let second = Segment(text: "needs a rewrite", start: 2.6, end: 3.9, isFinal: true)
    let scripted: [TranscriptEvent] = [
      .speechStarted(at: 0.8),
      .segment(Segment(text: "So the", start: 0.8, end: 1.2, isFinal: false)),
      .segment(Segment(text: "So the pricing", start: 0.8, end: 1.7, isFinal: false)),
      .segment(first),
      .speechEnded(at: 2.1),
      .speechStarted(at: 2.6),
      .segment(Segment(text: "needs a", start: 2.6, end: 3.0, isFinal: false)),
      .segment(second),
      .speechEnded(at: 3.9),
      .ended,
    ]
    for event in scripted {
      await recorder.record(event)
    }
    #expect(await recorder.finalCount == 2)
    let written = try await recorder.finish()
    #expect(written.segments == [first, second])

    let replay = try FixtureTranscriber(contentsOf: recorder.fixtureURL)
    var replayed: [TranscriptEvent] = []
    for await event in replay.events() {
      replayed.append(event)
    }
    #expect(
      replayed == [
        .speechStarted(at: 0.8), .segment(first), .speechEnded(at: 2.1),
        .speechStarted(at: 2.6), .segment(second), .speechEnded(at: 3.9),
        .ended,
      ])
  }

  @Test func sortsFinalsByStartTime() async throws {
    let recorder = try FixtureRecorder(directory: directory)
    let late = Segment(text: "later", start: 5, end: 6, isFinal: true)
    let early = Segment(text: "earlier", start: 1, end: 2, isFinal: true)
    await recorder.record(.segment(late))
    await recorder.record(.segment(early))
    let fixture = try await recorder.finish()
    #expect(fixture.segments == [early, late])
  }

  @Test func namesBothFilesFromTheSessionStart() throws {
    let start = Date(timeIntervalSince1970: 1_792_900_000)
    let utc = try #require(TimeZone(identifier: "UTC"))
    let recorder = try FixtureRecorder(directory: directory, sessionStart: start, timeZone: utc)
    #expect(recorder.fixtureURL.lastPathComponent == "2026-10-25-034640.json")
    #expect(recorder.audioURL.lastPathComponent == "2026-10-25-034640.caf")

    let pacific = try #require(TimeZone(secondsFromGMT: -7 * 3600))
    #expect(FixtureRecorder.baseName(for: start, timeZone: pacific) == "2026-10-24-204640")
  }

  @Test func writesTappedAudioToACAFThatReadsBackSampleForSample() async throws {
    let recorder = try FixtureRecorder(directory: directory)
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
    var expected: [Float] = []
    for chunk in 0..<3 {
      let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
      buffer.frameLength = 4800
      let samples = try #require(buffer.floatChannelData?[0])
      for frame in 0..<4800 {
        let t = Double(chunk * 4800 + frame) / 48000
        samples[frame] = Float(sin(2 * .pi * 440 * t)) * 0.5
        expected.append(samples[frame])
      }
      recorder.audio.write(buffer)
    }
    #expect(recorder.audio.framesWritten == 14400)
    try await recorder.finish()

    let file = try AVAudioFile(forReading: recorder.audioURL)
    #expect(recorder.audioURL.pathExtension == "caf")
    #expect(file.length == 14400)
    #expect(file.fileFormat.sampleRate == 48000)
    var actual: [Float] = []
    while file.framePosition < file.length {
      let chunk = try #require(
        AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
      try file.read(into: chunk)
      let samples = try #require(chunk.floatChannelData?[0])
      actual += UnsafeBufferPointer(start: samples, count: Int(chunk.frameLength))
    }
    #expect(actual == expected)
  }
}
