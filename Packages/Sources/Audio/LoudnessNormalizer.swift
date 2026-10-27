import AVFAudio
import Foundation

/// Brings one spoken line toward a target level, buffer by buffer, as the bytes arrive. The gain tracks the running RMS of the line's voiced blocks, so a soft line comes up and a hot one comes down, with a 10 ms ramp between buffers so nothing clicks. A limiter then holds every peak under the ceiling in 5 ms blocks, one block ahead, without clipping.
public struct LoudnessNormalizer {
  public static let targetDBFS: Float = -16
  public static let ceilingDBFS: Float = -1
  public static let maxGainDB: Float = 12
  /// The line's output, over its voiced blocks so far, may not land more than this far above the target.
  public static let overshootDB: Float = 3
  /// 20 ms blocks under this level are silence between words and do not count toward the line's level.
  public static let gateDBFS: Float = -50

  private let target = amplitude(targetDBFS)
  private let ceiling = amplitude(ceilingDBFS)
  private let maxGain = amplitude(maxGainDB)
  private let overshoot = amplitude(overshootDB)
  private let gate = amplitude(gateDBFS)
  /// The limiter lets go over 20 blocks, 100 ms.
  private let release: Float = 0.05
  private var sumSquares: Double = 0
  private var voiced = 0
  private var outSumSquares: Double = 0
  private var gain: Float = 1
  private var limiter: Float = 1

  public init() {}

  /// The gain the last buffer settled on, in dB, before the limiter. Zero until a voiced block has been heard.
  public var gainDB: Float { 20 * log10(gain) }

  /// Scales `buffer` in place. Silence leaves the gain where it is, so a quiet lead-in is not blown up.
  public mutating func apply(to buffer: AVAudioPCMBuffer) {
    guard let channels = buffer.floatChannelData else { return }
    let frames = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    guard frames > 0, channelCount > 0 else { return }
    let rate = buffer.format.sampleRate

    var voicedSum: Double = 0
    let gateBlock = max(1, Int(rate / 50))
    for channel in 0..<channelCount {
      let samples = channels[channel]
      var start = 0
      while start < frames {
        let end = min(start + gateBlock, frames)
        var sum: Double = 0
        for i in start..<end { sum += Double(samples[i] * samples[i]) }
        if sqrt(sum / Double(end - start)) > Double(gate) {
          voicedSum += sum
          voiced += end - start
        }
        start = end
      }
    }
    sumSquares += voicedSum

    var wanted = gain
    if voiced > 0 {
      let lineRMS = Float(sqrt(sumSquares / Double(voiced)))
      wanted = min(max(target / lineRMS, 1 / maxGain), maxGain)
    }
    if voicedSum > 0 {
      let room = Double(target * overshoot) * Double(target * overshoot) * Double(voiced)
      wanted = min(wanted, Float(sqrt(max(room - outSumSquares, 0) / voicedSum)))
      outSumSquares += Double(wanted) * Double(wanted) * voicedSum
    }

    let ramp = min(frames, max(1, Int(rate / 100)))
    let from = gain
    func gainAt(_ i: Int) -> Float {
      i >= ramp ? wanted : from + (wanted - from) * Float(i + 1) / Float(ramp)
    }

    let block = max(1, Int(rate / 200))
    let blocks = (frames + block - 1) / block
    var needed = [Float](repeating: 1, count: blocks)
    for b in 0..<blocks {
      var peak: Float = 0
      for channel in 0..<channelCount {
        let samples = channels[channel]
        for i in (b * block)..<min((b + 1) * block, frames) {
          peak = max(peak, abs(samples[i]) * gainAt(i))
        }
      }
      if peak > ceiling { needed[b] = ceiling / peak }
    }
    var envelope = needed
    for b in 0..<blocks {
      let ahead = b + 1 < blocks ? needed[b + 1] : 1
      let previous = b > 0 ? envelope[b - 1] : limiter
      envelope[b] = min(needed[b], ahead, previous + release)
    }
    for b in 0..<blocks {
      let previous = b > 0 ? envelope[b - 1] : limiter
      let start = b * block
      let end = min(start + block, frames)
      for i in start..<end {
        let t = Float(i - start + 1) / Float(end - start)
        let trim = min(previous + (envelope[b] - previous) * t, needed[b])
        let scale = gainAt(i) * trim
        for channel in 0..<channelCount { channels[channel][i] *= scale }
      }
    }
    limiter = envelope[blocks - 1]
    gain = wanted
  }
}

private func amplitude(_ dB: Float) -> Float {
  powf(10, dB / 20)
}
