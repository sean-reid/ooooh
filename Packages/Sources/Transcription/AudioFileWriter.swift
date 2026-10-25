import AVFAudio
import Foundation

/// Appends PCM buffers to one audio file. The file opens on the first buffer so it takes the tap's format.
public final class AudioFileWriter: AudioBufferSink, @unchecked Sendable {
  public let url: URL
  private let lock = NSLock()
  private var file: AVAudioFile?
  private var isClosed = false
  private var frames: AVAudioFramePosition = 0
  private var failure: (any Error)?

  public init(url: URL) {
    self.url = url
  }

  public var framesWritten: AVAudioFramePosition {
    lock.withLock { frames }
  }

  public func write(_ buffer: AVAudioPCMBuffer) {
    lock.withLock {
      guard !isClosed, failure == nil else { return }
      do {
        if file == nil {
          file = try AVAudioFile(
            forWriting: url, settings: buffer.format.settings,
            commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
        }
        try file?.write(from: buffer)
        frames += AVAudioFramePosition(buffer.frameLength)
      } catch {
        failure = error
      }
    }
  }

  /// Flushes and closes. Throws the first write error, if any.
  public func close() throws {
    try lock.withLock {
      isClosed = true
      file = nil
      if let failure { throw failure }
    }
  }
}
