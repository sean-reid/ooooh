import AVFAudio
import Foundation
import TestSupport
import Testing

@testable import Audio

/// The fixture is `say` output encoded with lame at 64 kbps, 44.1 kHz mono, the Worker's format.
enum Fixture {
  static func line() throws -> Data { try Bundle.module.fixture("line.mp3") }

  static func chunks(_ data: Data, size: Int) -> [Data] {
    stride(from: 0, to: data.count, by: size).map { data[$0..<min($0 + size, data.count)] }
  }

  /// PCM frames the fixture decodes to when fed in `size` byte chunks, the count a player schedules.
  static func frames(chunked size: Int) throws -> AVAudioFramePosition {
    let output = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
    let parser = try AudioStreamParser()
    let decoder = SpeechDecoder(output: output)
    var frames: AVAudioFramePosition = 0
    for chunk in chunks(try line(), size: size) {
      for packets in try parser.parse(chunk) {
        frames += AVAudioFramePosition(try decoder.decode(packets)?.frameLength ?? 0)
      }
    }
    return frames
  }
}

@Suite struct AudioStreamParserTests {
  @Test func readsTheFormatAndYieldsPacketsFromSmallChunks() throws {
    let parser = try AudioStreamParser()
    var bytesBeforeFirstPacket: Int?
    var fed = 0
    var packets = 0
    for chunk in Fixture.chunks(try Fixture.line(), size: 512) {
      fed += chunk.count
      let batches = try parser.parse(chunk)
      packets += batches.reduce(0) { $0 + $1.descriptions.count }
      if bytesBeforeFirstPacket == nil, packets > 0 { bytesBeforeFirstPacket = fed }
    }
    let format = try #require(parser.format)
    #expect(format.mFormatID == kAudioFormatMPEGLayer3)
    #expect(format.mSampleRate == 44100)
    #expect(format.mChannelsPerFrame == 1)
    #expect(format.mFramesPerPacket == 1152)
    #expect(packets > 100)
    let first = try #require(bytesBeforeFirstPacket)
    print("first mp3 packet after \(first) bytes")
    #expect(first <= 1024)
  }

  @Test func decodesToPcmWithinTheFirstKilobyte() throws {
    let output = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
    let parser = try AudioStreamParser()
    let decoder = SpeechDecoder(output: output)
    var fed = 0
    var frames: AVAudioFrameCount = 0
    var bytesBeforeFirstPcm: Int?
    for chunk in Fixture.chunks(try Fixture.line(), size: 512) {
      fed += chunk.count
      for packets in try parser.parse(chunk) {
        guard let pcm = try decoder.decode(packets) else { continue }
        #expect(pcm.format == output)
        frames += pcm.frameLength
        if bytesBeforeFirstPcm == nil { bytesBeforeFirstPcm = fed }
      }
    }
    let first = try #require(bytesBeforeFirstPcm)
    let seconds = Double(frames) / output.sampleRate
    print("first pcm after \(first) bytes, \(frames) frames, \(seconds) s")
    #expect(first <= 1024)
    #expect(seconds > 2.9 && seconds < 3.3)
  }
}
