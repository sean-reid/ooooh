import AVFAudio
import Accelerate
import Transcription

/// Turns every microphone buffer into one voice level from 0 to 1.
final class AudioLevelMeter: AudioBufferSink, Sendable {
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
    let decibels = 20 * log10(max(rms, 1e-6))
    continuation.yield(Double(min(max((decibels + 50) / 44, 0), 1)))
  }
}
