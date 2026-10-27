import AVFAudio
import Foundation
import Speech

extension SpeechRecognizerTranscriber {
  /// Whether the recognizer for `locale` runs on this machine without the network.
  public static func supportsOnDeviceRecognition(locale: Locale) -> Bool {
    SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
  }

  /// Runs an audio file through the microphone path: the same requests, rotation, and utterance
  /// splitting, fed at `speed` times real time so the pause timers fire as they do live.
  /// Returns the final segments in order, timed from the start of the file.
  public static func transcribe(
    file: URL, locale: Locale, onDevice: Bool, speed: Double = 1
  ) async throws -> [Segment] {
    try await transcribe(
      file: file, recognizer: LiveRecognizer(locale: locale), locale: locale, onDevice: onDevice,
      speed: speed)
  }

  static func transcribe(
    file: URL, recognizer: any SpeechRecognizing, locale: Locale, onDevice: Bool, speed: Double
  ) async throws -> [Segment] {
    let transcriber = SpeechRecognizerTranscriber(
      recognizer: recognizer, locale: locale, onDevice: onDevice)
    let audio = try AVAudioFile(forReading: file)
    let format = audio.processingFormat
    let collector = Task { () -> [Segment] in
      var finals: [Segment] = []
      for await event in transcriber.events() {
        if case .segment(let segment) = event, segment.isFinal { finals.append(segment) }
      }
      return finals
    }
    try await transcriber.beginRecognition()
    let clock = ContinuousClock()
    let started = clock.now
    var fed: TimeInterval = 0
    while audio.framePosition < audio.length {
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { break }
      try audio.read(into: buffer)
      if buffer.frameLength == 0 { break }
      if transcriber.feed.append(buffer) { await transcriber.rotateAtLimit() }
      fed += Double(buffer.frameLength) / format.sampleRate
      if speed.isFinite, speed > 0 {
        let due = started + .seconds(fed / speed)
        if due > clock.now { try await Task.sleep(until: due, clock: clock) }
      }
    }
    await transcriber.stop()
    return await collector.value
  }
}
