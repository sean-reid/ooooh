import AVFAudio
import Accelerate
import Foundation

/// Folds tap buffers into log reports: the first buffer, then one per `interval` seconds of audio
/// with the buffer count and the loudest RMS in it. A tap that never fires reports nothing.
struct TapWindow: Equatable {
  enum Report: Equatable {
    case first(frames: Int, rms: Float)
    case window(buffers: Int, peakRMS: Float, audioTime: TimeInterval)
  }

  let interval: TimeInterval
  private(set) var audioTime: TimeInterval = 0
  private var buffers = 0
  private var peakRMS: Float = 0
  private var windowEnd: TimeInterval
  private var started = false

  init(interval: TimeInterval = 5) {
    self.interval = interval
    windowEnd = interval
  }

  mutating func record(frames: Int, sampleRate: Double, rms: Float) -> Report? {
    audioTime += Double(frames) / sampleRate
    buffers += 1
    peakRMS = max(peakRMS, rms)
    if !started {
      started = true
      return .first(frames: frames, rms: rms)
    }
    guard audioTime >= windowEnd else { return nil }
    let report = Report.window(buffers: buffers, peakRMS: peakRMS, audioTime: audioTime)
    buffers = 0
    peakRMS = 0
    while windowEnd <= audioTime { windowEnd += interval }
    return report
  }
}

extension TapWindow.Report {
  /// The report as the log line carries it.
  var line: String {
    switch self {
    case .first(let frames, let rms):
      "tap first buffer frames=\(frames) rms=\(Self.format(rms))"
    case .window(let buffers, let peakRMS, let audioTime):
      "tap window buffers=\(buffers) peakRms=\(Self.format(peakRMS)) audioTime=\(Int(audioTime))"
    }
  }

  private static func format(_ rms: Float) -> String {
    String(format: "%.4f", rms)
  }
}

/// Runs the window on the tap's thread and writes its reports to the transcription log.
final class TapMonitor: @unchecked Sendable {
  private let engine: TranscriptionEngine
  private let lock = NSLock()
  private var window = TapWindow()

  init(engine: TranscriptionEngine) {
    self.engine = engine
  }

  var audioTime: TimeInterval { lock.withLock { window.audioTime } }

  func observe(_ buffer: AVAudioPCMBuffer) {
    let frames = Int(buffer.frameLength)
    let rms = Self.rms(of: buffer)
    let report = lock.withLock {
      window.record(frames: frames, sampleRate: buffer.format.sampleRate, rms: rms)
    }
    guard let report else { return }
    transcriptionLog.info(
      "\(report.line, privacy: .public) engine=\(self.engine.rawValue, privacy: .public)")
  }

  /// Zero for a buffer that is not float, which the input format line already shows.
  static func rms(of buffer: AVAudioPCMBuffer) -> Float {
    let frames = Int(buffer.frameLength)
    guard frames > 0, let samples = buffer.floatChannelData?[0] else { return 0 }
    return vDSP.rootMeanSquare(UnsafeBufferPointer(start: samples, count: frames))
  }
}

extension AVAudioFormat {
  /// "48000Hz ch=1 fmt=1", the three numbers a tap line needs.
  var logDescription: String {
    "\(Int(sampleRate))Hz ch=\(channelCount) fmt=\(commonFormat.rawValue)"
  }
}
