import AVFAudio
import Testing

@testable import ooooh

@Suite struct AudioLevelMeterTests {
  @Test func phoneSpeechReadsAsMotionAndRoomToneAsRest() {
    #expect(AudioLevelMeter.level(rms: 0.0006) < 0.05)
    #expect(AudioLevelMeter.level(rms: 0.003) > 0.3)
    #expect(AudioLevelMeter.level(rms: 0.0075) > 0.45)
    #expect(AudioLevelMeter.level(rms: 0.1) == 1)
    #expect(AudioLevelMeter.level(rms: 0) == 0)
  }

  @Test func aBufferYieldsTheLevelOfItsRMS() async throws {
    let meter = AudioLevelMeter()
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
    buffer.frameLength = 4800
    let samples = try #require(buffer.floatChannelData?[0])
    for frame in 0..<4800 { samples[frame] = frame.isMultiple(of: 2) ? 0.0075 : -0.0075 }
    var iterator = meter.levels().makeAsyncIterator()
    meter.write(buffer)
    let level = try #require(await iterator.next())
    #expect(abs(level - AudioLevelMeter.level(rms: 0.0075)) < 0.001)
  }
}
