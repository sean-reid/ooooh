import AVFAudio

/// Resamples tap buffers into the analyzer's format. Only the tap thread touches the converter.
final class BufferConverter: @unchecked Sendable {
  let outputFormat: AVAudioFormat
  private let converter: AVAudioConverter

  init?(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) {
    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
    converter.primeMethod = .none
    self.converter = converter
    self.outputFormat = outputFormat
  }

  func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    if buffer.format == outputFormat { return buffer }
    let ratio = outputFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
    guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
      return nil
    }
    nonisolated(unsafe) let input = buffer
    nonisolated(unsafe) var consumed = false
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return input
    }
    return status == .error ? nil : output
  }
}
