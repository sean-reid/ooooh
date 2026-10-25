import AudioToolbox
import Foundation

public enum SpeechError: Error, Equatable, Sendable {
  case parse(OSStatus)
  case format
  case decode(String)
}

/// Cuts an MP3 byte stream into packets with AudioFileStream. Bytes arrive in any chunking; packets come out as soon as they are whole.
public final class AudioStreamParser {
  public struct Packets: Sendable {
    public var format: AudioStreamBasicDescription
    public var maxPacketSize: UInt32
    public var data: Data
    public var descriptions: [AudioStreamPacketDescription]
  }

  private var stream: AudioFileStreamID?
  private var pending: [Packets] = []
  public private(set) var format: AudioStreamBasicDescription?
  public private(set) var maxPacketSize: UInt32 = 0

  public init(fileType: AudioFileTypeID = kAudioFileMP3Type) throws {
    let status = AudioFileStreamOpen(
      Unmanaged.passUnretained(self).toOpaque(), onProperty, onPackets, fileType, &stream)
    guard status == noErr else { throw SpeechError.parse(status) }
  }

  deinit {
    if let stream { AudioFileStreamClose(stream) }
  }

  /// Returns every packet batch these bytes completed, possibly none.
  public func parse(_ data: Data) throws -> [Packets] {
    guard let stream else { throw SpeechError.parse(kAudioFileStreamError_InvalidFile) }
    let status = data.withUnsafeBytes { bytes in
      AudioFileStreamParseBytes(stream, UInt32(bytes.count), bytes.baseAddress, [])
    }
    guard status == noErr else { throw SpeechError.parse(status) }
    defer { pending.removeAll() }
    return pending
  }

  fileprivate func property(_ id: AudioFileStreamPropertyID, in stream: AudioFileStreamID) {
    guard id == kAudioFileStreamProperty_ReadyToProducePackets else { return }
    var description = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    if AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_DataFormat, &size, &description)
      == noErr
    {
      format = description
    }
    var upperBound: UInt32 = 0
    size = UInt32(MemoryLayout<UInt32>.size)
    if AudioFileStreamGetProperty(
      stream, kAudioFileStreamProperty_PacketSizeUpperBound, &size, &upperBound) == noErr
    {
      maxPacketSize = upperBound
    }
  }

  fileprivate func packets(
    byteCount: UInt32, packetCount: UInt32, bytes: UnsafeRawPointer,
    descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
  ) {
    guard let format else { return }
    let data = Data(bytes: bytes, count: Int(byteCount))
    let count = Int(packetCount)
    let list: [AudioStreamPacketDescription]
    if let descriptions {
      list = Array(UnsafeBufferPointer(start: descriptions, count: count))
    } else {
      let size = format.mBytesPerPacket
      list = (0..<count).map {
        AudioStreamPacketDescription(
          mStartOffset: Int64($0) * Int64(size), mVariableFramesInPacket: 0, mDataByteSize: size)
      }
    }
    let largest = list.map(\.mDataByteSize).max() ?? 0
    pending.append(
      Packets(
        format: format, maxPacketSize: max(maxPacketSize, largest), data: data, descriptions: list)
    )
  }
}

private let onProperty: AudioFileStream_PropertyListenerProc = { client, stream, property, _ in
  Unmanaged<AudioStreamParser>.fromOpaque(client).takeUnretainedValue()
    .property(property, in: stream)
}

private let onPackets: AudioFileStream_PacketsProc = {
  client, byteCount, packetCount, bytes, descriptions in
  Unmanaged<AudioStreamParser>.fromOpaque(client).takeUnretainedValue()
    .packets(
      byteCount: byteCount, packetCount: packetCount, bytes: bytes, descriptions: descriptions)
}
