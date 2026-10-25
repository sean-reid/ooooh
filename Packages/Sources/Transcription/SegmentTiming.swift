import CoreMedia
import Foundation

extension Segment {
  /// Analyzer time starts at the first buffer fed, so these seconds are relative to session start.
  public init(text: String, range: CMTimeRange, isFinal: Bool) {
    let start = Self.seconds(range.start)
    self.init(text: text, start: start, end: max(start, Self.seconds(range.end)), isFinal: isFinal)
  }

  static func seconds(_ time: CMTime) -> TimeInterval {
    guard time.isNumeric else { return 0 }
    return max(0, time.seconds)
  }
}

/// Derives speech boundaries from result timing: the first result of an utterance opens it, the final result closes it.
struct VoiceActivity {
  private(set) var isSpeaking = false
  private var lastEnd: TimeInterval = 0

  mutating func events(for segment: Segment) -> [TranscriptEvent] {
    var events: [TranscriptEvent] = []
    if !isSpeaking {
      isSpeaking = true
      events.append(.speechStarted(at: segment.start))
    }
    events.append(.segment(segment))
    lastEnd = max(lastEnd, segment.end)
    if segment.isFinal {
      isSpeaking = false
      events.append(.speechEnded(at: segment.end))
    }
    return events
  }

  mutating func close() -> [TranscriptEvent] {
    guard isSpeaking else { return [] }
    isSpeaking = false
    return [.speechEnded(at: lastEnd)]
  }
}
