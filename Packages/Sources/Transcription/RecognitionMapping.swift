import AVFAudio
import Foundation

/// One word of a recognizer transcription, timed from the start of its request's audio.
struct RecognizedWord: Equatable, Sendable {
  var text: String
  var timestamp: TimeInterval
  var duration: TimeInterval

  var end: TimeInterval { timestamp + duration }
}

/// A recognizer result as the mapping sees it: the whole transcription of one request so far.
struct RecognitionResult: Equatable, Sendable {
  var words: [RecognizedWord]
  var isFinal: Bool
}

/// Cuts one request's growing transcription into utterances at pauses. An utterance is final once
/// the recognizer has moved past it or `flush` says the speaker has stopped; the words after that
/// are volatile. Times are session seconds: the request's offset plus the words' own, or the audio
/// clock when a result carries no word timing.
struct UtteranceSplitter {
  let offset: TimeInterval
  let pause: TimeInterval
  private(set) var settledWords = 0
  private var last: RecognitionResult?
  private var pendingSince: TimeInterval?
  private var lastHeardAt: TimeInterval = 0

  init(offset: TimeInterval, pause: TimeInterval = 1) {
    self.offset = offset
    self.pause = pause
  }

  mutating func segments(for result: RecognitionResult, at audioTime: TimeInterval) -> [Segment] {
    last = result
    lastHeardAt = audioTime
    guard result.words.count > settledWords else { return [] }
    if pendingSince == nil { pendingSince = audioTime }
    let pending = Array(result.words[settledWords...])
    let utterances = Self.split(pending, pause: pause)
    var segments: [Segment] = []
    let settled = result.isFinal ? utterances.count : utterances.count - 1
    for utterance in utterances.prefix(settled) {
      segments.append(segment(utterance, isFinal: true, now: audioTime))
      settledWords += utterance.count
      pendingSince = audioTime
    }
    if !result.isFinal, let open = utterances.last {
      segments.append(segment(open, isFinal: false, now: audioTime))
    }
    if result.isFinal { pendingSince = nil }
    return segments
  }

  /// Finalizes whatever the last result left open, for a pause the recognizer has not reported.
  mutating func flush(at audioTime: TimeInterval) -> Segment? {
    guard let last, last.words.count > settledWords else { return nil }
    let pending = Array(last.words[settledWords...])
    let flushed = segment(pending, isFinal: true, now: lastHeardAt, flushedAt: audioTime)
    settledWords = last.words.count
    pendingSince = nil
    return flushed
  }

  private func segment(
    _ words: [RecognizedWord], isFinal: Bool, now: TimeInterval, flushedAt: TimeInterval? = nil
  ) -> Segment {
    let text = words.map(\.text).joined(separator: " ")
    if Self.timed(words), let first = words.first, let lastWord = words.last {
      return Segment(
        text: text, start: offset + first.timestamp, end: offset + lastWord.end, isFinal: isFinal)
    }
    let start = pendingSince ?? now
    return Segment(text: text, start: start, end: max(start, flushedAt ?? now), isFinal: isFinal)
  }

  static func split(_ words: [RecognizedWord], pause: TimeInterval) -> [[RecognizedWord]] {
    guard timed(words) else { return words.isEmpty ? [] : [words] }
    var utterances: [[RecognizedWord]] = []
    for word in words {
      if let previous = utterances.last?.last, word.timestamp - previous.end < pause {
        utterances[utterances.count - 1].append(word)
      } else {
        utterances.append([word])
      }
    }
    return utterances
  }

  /// Partial results from the on-device recognizer can carry zero for every time.
  private static func timed(_ words: [RecognizedWord]) -> Bool {
    words.contains { $0.timestamp > 0 || $0.duration > 0 }
  }
}

/// Anything tap buffers can be appended to; the recognizer's request is the live one.
protocol AudioAppending: AnyObject {
  func append(_ buffer: AVAudioPCMBuffer)
}

/// Hands tap buffers to the live request and keeps the audio clock, on the tap's thread.
final class RequestFeed<Request: AudioAppending>: @unchecked Sendable {
  let limit: TimeInterval
  private let lock = NSLock()
  private var request: Request?
  private var fed: TimeInterval = 0
  private var requestStart: TimeInterval = 0
  private var limitReported = false

  init(limit: TimeInterval) {
    self.limit = limit
  }

  /// Seconds of audio seen since the first buffer.
  var audioTime: TimeInterval { lock.withLock { fed } }

  /// Seconds of audio the live request has heard.
  var elapsedInRequest: TimeInterval { lock.withLock { fed - requestStart } }

  /// Appends to the live request. True once per request, when it has heard `limit` seconds.
  func append(_ buffer: AVAudioPCMBuffer) -> Bool {
    lock.withLock {
      fed += Double(buffer.frameLength) / buffer.format.sampleRate
      request?.append(buffer)
      guard request != nil, !limitReported, fed - requestStart >= limit else { return false }
      limitReported = true
      return true
    }
  }

  /// Makes `next` the live request. Returns the one it replaced and the audio time `next` starts at.
  func swap(in next: Request?) -> (previous: Request?, start: TimeInterval) {
    lock.withLock {
      let previous = request
      request = next
      requestStart = fed
      limitReported = false
      return (previous, fed)
    }
  }
}
