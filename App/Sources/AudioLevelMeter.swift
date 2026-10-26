import AVFAudio
import Accelerate
import Transcription

/// Turns every microphone buffer into one voice level from 0 to 1.
final class AudioLevelMeter: AudioBufferSink, Sendable {
  /// A phone microphone hears room tone near -65 dBFS and speech at arm's length near -45.
  nonisolated static let floorDecibels = -65.0
  nonisolated static let rangeDecibels = 45.0

  private let stream: AsyncStream<Double>
  private let continuation: AsyncStream<Double>.Continuation

  init() {
    (stream, continuation) = AsyncStream.makeStream(of: Double.self)
  }

  func levels() -> AsyncStream<Double> { stream }

  func write(_ buffer: AVAudioPCMBuffer) {
    let frames = Int(buffer.frameLength)
    guard frames > 0, let samples = buffer.floatChannelData?[0] else { return }
    let rms = vDSP.rootMeanSquare(UnsafeBufferPointer(start: samples, count: frames))
    continuation.yield(Self.level(rms: Double(rms)))
  }

  nonisolated static func level(rms: Double) -> Double {
    let decibels = 20 * log10(max(rms, 1e-6))
    return min(max((decibels - floorDecibels) / rangeDecibels, 0), 1)
  }
}
