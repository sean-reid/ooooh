import Foundation
import State
import Transcription

/// What a screen needs to know about a running session, in the order it happened.
public enum SessionEvent: Sendable {
  case speechLevel(Double)
  case speechStarted(at: TimeInterval)
  case speechEnded(at: TimeInterval)
  case utterance(Segment)
  case promptPending(InterventionKind)
  case promptRequested(kind: InterventionKind, text: String, at: TimeInterval)
  case askedIfFinished(at: TimeInterval)
  case compactionApplied(CompactState, at: TimeInterval)
  case offline(Bool)
  case ended(SessionResult)
}
