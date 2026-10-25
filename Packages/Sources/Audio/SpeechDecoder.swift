import AVFAudio
import Foundation

/// Turns parsed packets into PCM for the player, one batch at a time, keeping decoder state between batches.
public final class SpeechDecoder {
  public let output: AVAudioFormat
  private var input: AVAudioFormat?
  private var converter: AVAudioConverter?

  public init(output: AVAudioFormat) {
    self.output = output
  }

  /// PCM for one batch, or nil while the decoder is still priming.
  public func decode(_ packets: AudioStreamParser.Packets) throws -> AVAudioPCMBuffer? {
    let (input, converter) = try prepared(for: packets)
    let count = packets.descriptions.count
    guard count > 0 else { return nil }
    let compressed = AVAudioCompressedBuffer(
      format: input, packetCapacity: AVAudioPacketCount(count),
      maximumPacketSize: Int(packets.maxPacketSize))
    packets.data.withUnsafeBytes { bytes in
      compressed.data.copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
    }
    compressed.byteLength = UInt32(packets.data.count)
    compressed.packetCount = AVAudioPacketCount(count)
    if let descriptions = compressed.packetDescriptions {
      for (i, description) in packets.descriptions.enumerated() { descriptions[i] = description }
    }

    let framesPerPacket = max(Int(packets.format.mFramesPerPacket), 1152)
    let ratio = output.sampleRate / packets.format.mSampleRate
    let capacity = AVAudioFrameCount(Double((count + 2) * framesPerPacket) * ratio)
    guard let pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else {
      throw SpeechError.format
    }
    // The input block runs synchronously inside convert, on this thread.
    nonisolated(unsafe) var handed = false
    nonisolated(unsafe) let source = compressed
    var error: NSError?
    let status = converter.convert(to: pcm, error: &error) { _, outStatus in
      if handed {
        outStatus.pointee = .noDataNow
        return nil
      }
      handed = true
      outStatus.pointee = .haveData
      return source
    }
    if status == .error { throw SpeechError.decode(error?.localizedDescription ?? "convert") }
    return pcm.frameLength > 0 ? pcm : nil
  }

  private func prepared(for packets: AudioStreamParser.Packets) throws -> (
    AVAudioFormat, AVAudioConverter
  ) {
    if let input, let converter { return (input, converter) }
    var description = packets.format
    guard let input = AVAudioFormat(streamDescription: &description),
      let converter = AVAudioConverter(from: input, to: output)
    else { throw SpeechError.format }
    self.input = input
    self.converter = converter
    return (input, converter)
  }
}
