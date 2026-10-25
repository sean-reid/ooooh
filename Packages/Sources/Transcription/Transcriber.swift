import Foundation

/// A piece of recognized speech. Partial results are replaced by the final one for the same range.
public struct Segment: Codable, Equatable, Sendable {
  public var text: String
  public var start: TimeInterval
  public var end: TimeInterval
  public var isFinal: Bool

  public init(text: String, start: TimeInterval, end: TimeInterval, isFinal: Bool) {
    self.text = text
    self.start = start
    self.end = end
    self.isFinal = isFinal
  }
}

public enum TranscriptEvent: Equatable, Sendable {
  case segment(Segment)
  case speechStarted(at: TimeInterval)
  case speechEnded(at: TimeInterval)
  case ended
}

/// Anything that turns audio into timed text. The live one wraps SpeechAnalyzer, the fixture one replays a file.
public protocol Transcriber: Sendable {
  func events() -> AsyncStream<TranscriptEvent>
  func stop() async
}
