import AVFAudio
import Foundation
import Testing

@testable import Audio

/// Peak and RMS of a run of buffers in dBFS, the voiced figure gated the way the normalizer gates.
struct Level {
  var peak: Float = 0
  var sumSquares: Double = 0
  var frames = 0
  var voicedSquares: Double = 0
  var voicedFrames = 0

  mutating func add(_ buffer: AVAudioPCMBuffer) {
    let samples = buffer.floatChannelData![0]
    let gate = powf(10, LoudnessNormalizer.gateDBFS / 20)
    let block = Int(buffer.format.sampleRate / 50)
    for start in stride(from: 0, to: Int(buffer.frameLength), by: block) {
      let end = min(start + block, Int(buffer.frameLength))
      var sum: Double = 0
      for i in start..<end {
        peak = max(peak, abs(samples[i]))
        sum += Double(samples[i] * samples[i])
      }
      sumSquares += sum
      if sqrt(sum / Double(end - start)) > Double(gate) {
        voicedSquares += sum
        voicedFrames += end - start
      }
    }
    frames += Int(buffer.frameLength)
  }

  var peakDB: Float { 20 * log10(peak) }
  var rmsDB: Float { 20 * log10(Float(sqrt(sumSquares / Double(max(frames, 1))))) }
  var voicedDB: Float { 20 * log10(Float(sqrt(voicedSquares / Double(max(voicedFrames, 1))))) }
}

@Suite struct LoudnessNormalizerTests {
  let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
  let target = LoudnessNormalizer.targetDBFS
  let ceiling = LoudnessNormalizer.ceilingDBFS

  /// 130 ms of a 440 Hz sine with the given RMS, about the size of one decoded network chunk.
  func tone(rmsDB: Float, frames: AVAudioFrameCount = 5760) -> AVAudioPCMBuffer {
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let amplitude = powf(10, rmsDB / 20) * sqrtf(2)
    let samples = buffer.floatChannelData![0]
    for i in 0..<Int(frames) {
      samples[i] = amplitude * sinf(2 * .pi * 440 * Float(i) / 44100)
    }
    return buffer
  }

  func silence(frames: AVAudioFrameCount = 5760) -> AVAudioPCMBuffer {
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    return buffer
  }

  func level(_ buffer: AVAudioPCMBuffer) -> Level {
    var level = Level()
    level.add(buffer)
    return level
  }

  @Test func bringsTheFixtureToTheTargetWithoutPassingTheCeiling() throws {
    let parser = try AudioStreamParser()
    let decoder = SpeechDecoder(output: format)
    var normalizer = LoudnessNormalizer()
    var before = Level()
    var after = Level()
    for chunk in Fixture.chunks(try Fixture.line(), size: 1024) {
      for packets in try parser.parse(chunk) {
        guard let pcm = try decoder.decode(packets) else { continue }
        before.add(pcm)
        normalizer.apply(to: pcm)
        after.add(pcm)
      }
    }
    print(
      "fixture before: peak \(before.peakDB), rms \(before.rmsDB), voiced \(before.voicedDB) dBFS;"
        + " after: peak \(after.peakDB), rms \(after.rmsDB), voiced \(after.voicedDB) dBFS;"
        + " gain \(normalizer.gainDB) dB")
    #expect(before.voicedDB < -19)
    #expect(abs(after.voicedDB - target) < 1)
    #expect(after.rmsDB < target)
    #expect(after.peakDB <= ceiling + 0.01)
    #expect(after.voicedDB - before.voicedDB > 3)
  }

  @Test func silenceGetsNoGain() {
    var normalizer = LoudnessNormalizer()
    for _ in 0..<5 {
      let buffer = silence()
      normalizer.apply(to: buffer)
      #expect(level(buffer).peak == 0)
    }
    #expect(normalizer.gainDB == 0)
    let faint = tone(rmsDB: -70)
    normalizer.apply(to: faint)
    #expect(normalizer.gainDB == 0)
    #expect(abs(level(faint).rmsDB - -70) < 0.1)
  }

  @Test func gainStopsAtTwelveDecibels() {
    var normalizer = LoudnessNormalizer()
    let quiet = tone(rmsDB: -40)
    normalizer.apply(to: quiet)
    #expect(abs(normalizer.gainDB - LoudnessNormalizer.maxGainDB) < 0.01)
    #expect(abs(level(quiet).rmsDB - -28) < 0.2)
  }

  @Test func aHotLineComesDownToTheTarget() {
    var normalizer = LoudnessNormalizer()
    normalizer.apply(to: tone(rmsDB: -8))
    let settled = tone(rmsDB: -8)
    normalizer.apply(to: settled)
    #expect(abs(normalizer.gainDB - -8) < 0.01)
    #expect(abs(level(settled).rmsDB - target) < 0.2)
  }

  /// A line that climbs 6 dB every buffer, from a whisper to a shout, is the case where a running gain overshoots: the early gain was set by the quiet part.
  @Test func aCrescendoLineNeverLandsOverTheTargetByMoreThanThree() {
    var normalizer = LoudnessNormalizer()
    var out = Level()
    for step in 0..<8 {
      let buffer = tone(rmsDB: -50 + Float(step) * 6)
      normalizer.apply(to: buffer)
      out.add(buffer)
      #expect(normalizer.gainDB <= LoudnessNormalizer.maxGainDB + 0.01)
      #expect(level(buffer).peakDB <= ceiling + 0.01)
    }
    print("crescendo line landed at \(out.rmsDB) dBFS")
    #expect(out.rmsDB <= target + LoudnessNormalizer.overshootDB + 0.1)
    #expect(out.rmsDB > target - 3)
  }

  /// A line at -20 dBFS gets 4 dB; a spike at -1 dBFS inside it would clip, so the limiter must catch that one block and leave the rest.
  @Test func theLimiterHoldsTheCeilingAndTouchesOnlyThePeak() {
    var normalizer = LoudnessNormalizer()
    normalizer.apply(to: tone(rmsDB: -20))
    let spiked = tone(rmsDB: -20)
    let samples = spiked.floatChannelData![0]
    for i in 3000..<3010 { samples[i] = 0.9 }
    normalizer.apply(to: spiked)
    #expect(level(spiked).peakDB <= ceiling + 0.01)
    #expect(abs(normalizer.gainDB - 4) < 0.5)
    let untouched = (500..<2000).map { abs(samples[$0]) }.max()!
    #expect(untouched > 0.2)
    #expect(abs(level(spiked).rmsDB - target) < 1)
  }

  @Test func gainRampsInsteadOfStepping() {
    var normalizer = LoudnessNormalizer()
    let buffer = tone(rmsDB: -30)
    let samples = buffer.floatChannelData![0]
    let first = abs(samples[1])
    normalizer.apply(to: buffer)
    #expect(abs(samples[1]) < first * 2)
    #expect(abs(samples[1000]) > first * 2)
  }
}
