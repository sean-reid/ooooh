import Foundation
import State
import Transcription

/// What a screen needs to know about a running session, in the order it happened.
public enum SessionEvent: Sendable {
  case speechLevel(Double)
  case speechStarted(at: TimeInterval)
  case speechEnded(at: TimeInterval)
  case utterance(Segment)
  /// A decision landed at an utterance end and waits for the pause to hold; show about-to-speak.
  case promptArmed(at: TimeInterval, kind: ArmedPrompt)
  /// Speech resumed before the pause held, so the armed decision never speaks; drop about-to-speak.
  case promptCancelled(at: TimeInterval)
  /// The pause held; speak this now.
  case promptRequested(kind: InterventionKind, text: String, at: TimeInterval)
  /// The pause held after a finished decision; ask the finished question now.
  case askedIfFinished(at: TimeInterval)
  case compactionApplied(CompactState, at: TimeInterval)
  case offline(Bool)
  case ended(SessionResult)
}
