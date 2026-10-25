import AVFAudio

/// Receives every microphone buffer the tap sees, on the tap's thread, before conversion.
public protocol AudioBufferSink: Sendable {
  func write(_ buffer: AVAudioPCMBuffer)
}
