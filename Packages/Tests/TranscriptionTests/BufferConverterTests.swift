import AVFAudio
import Testing

@testable import Transcription

@Suite struct BufferConverterTests {
  @Test func resamplesToTheOutputRate() throws {
    let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
    let output = try #require(
      AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)
    )
    let converter = try #require(BufferConverter(from: input, to: output))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4800))
    buffer.frameLength = 4800
    let converted = try #require(converter.convert(buffer))
    #expect(converted.format == output)
    #expect(converted.frameLength == 1600)
  }

  @Test func passesMatchingFormatsThrough() throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
    let converter = try #require(BufferConverter(from: format, to: format))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
    buffer.frameLength = 160
    #expect(converter.convert(buffer) === buffer)
  }
}
