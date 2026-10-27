import AVFAudio
import Foundation
import Testing

@testable import Audio

/// The fixture is `say` output encoded with lame at 64 kbps, 44.1 kHz mono, the Worker's format.
enum Fixture {
  static func line() throws -> Data {
    let url = try #require(
      Bundle.module.url(forResource: "line", withExtension: "mp3", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }

  static func chunks(_ data: Data, size: Int) -> [Data] {
    stride(from: 0, to: data.count, by: size).map { data[$0..<min($0 + size, data.count)] }
  }

  /// PCM frames the fixture decodes to when fed in `size` byte chunks, the count a player schedules.
  /// `count` limits the decode to the first chunks.
  static func frames(chunked size: Int, count: Int = .max) throws -> AVAudioFramePosition {
    try decoded(chunked: size, count: count).reduce(0) { $0 + AVAudioFramePosition($1.frameLength) }
  }

  /// The PCM buffers the fixture decodes to, in the order a player schedules them.
  static func decoded(chunked size: Int, count: Int = .max) throws -> [AVAudioPCMBuffer] {
    let output = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
    let parser = try AudioStreamParser()
    let decoder = SpeechDecoder(output: output)
    var buffers: [AVAudioPCMBuffer] = []
    for chunk in chunks(try line(), size: size).prefix(count) {
      for packets in try parser.parse(chunk) {
        if let pcm = try decoder.decode(packets) { buffers.append(pcm) }
      }
    }
    return buffers
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
