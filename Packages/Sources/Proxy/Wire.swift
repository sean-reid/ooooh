import Foundation
import Governor
import State
import Transcription

/// The segment fields the Worker reads.
struct WireSegment: Encodable {
  var text: String
  var start: TimeInterval
  var end: TimeInterval

  init(_ segment: Segment) {
    text = segment.text
    start = segment.start
    end = segment.end
  }
}

struct WireSignals: Encodable {
  var pauseLength: TimeInterval
  var speechDensity: Double
  var awaitingFinishedReply: Bool
  var secondsSinceStart: TimeInterval
  var wordsSoFar: Int
  var promptsSoFar: Int
  var secondsSincePrompt: TimeInterval?

  init(_ signals: Signals) {
    pauseLength = signals.pauseLength
    speechDensity = signals.speechDensity
    awaitingFinishedReply = signals.awaitingFinishedReply
    secondsSinceStart = signals.now
    wordsSoFar = signals.wordsSoFar
    promptsSoFar = signals.promptsSoFar
    secondsSincePrompt = signals.secondsSincePrompt
  }
}

public struct ProviderUsage: Codable, Equatable, Sendable {
  public var jevInputTokens: Int?
  public var inputTokens: Int?
  public var outputTokens: Int?
}
