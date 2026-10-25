import Foundation
import Governor
import State
import Transcription

/// What an armed decision says once the pause after the utterance holds for the arming delay.
public enum ArmedPrompt: Equatable, Sendable {
  case intervention(InterventionKind)
  case finishedQuestion
}

/// Everything the loop did, in order, with the fixture clock. The eval reads these.
public enum SessionRecord: Equatable, Sendable {
  case check(at: TimeInterval, index: Int, answers: JevAnswers, decision: Decision)
  /// A decision at `at` waiting for the pause to hold.
  case promptArmed(at: TimeInterval, kind: ArmedPrompt)
  /// Speech resumed at `at` before the armed decision spoke, so it never will.
  case promptCancelled(at: TimeInterval)
  case prompt(at: TimeInterval, kind: InterventionKind, text: String)
  case askedIfFinished(at: TimeInterval)
  case command(at: TimeInterval, JevAnswers.Command)
  case compaction(at: TimeInterval, patch: StatePatch)
  case compactionRejected(at: TimeInterval, reason: String)
  case ended(at: TimeInterval, byUser: Bool)

  public var at: TimeInterval {
    switch self {
    case .check(let at, _, _, _), .promptArmed(let at, _), .promptCancelled(let at),
      .prompt(let at, _, _), .askedIfFinished(let at), .command(let at, _),
      .compaction(let at, _), .compactionRejected(let at, _), .ended(let at, _):
      at
    }
  }
}

public struct SessionResult: Sendable {
  public var records: [SessionRecord]
  public var state: CompactState
  public var transcript: [Segment]

  public var prompts: [(at: TimeInterval, kind: InterventionKind)] {
    records.compactMap {
      if case .prompt(let at, let kind, _) = $0 { (at, kind) } else { nil }
    }
  }

  public var commands: [(at: TimeInterval, command: JevAnswers.Command)] {
    records.compactMap {
      if case .command(let at, let command) = $0 { (at, command) } else { nil }
    }
  }

  public var finishedAsks: [TimeInterval] {
    records.compactMap {
      if case .askedIfFinished(let at) = $0 { at } else { nil }
    }
  }

  public var cancelledArms: [TimeInterval] {
    records.compactMap {
      if case .promptCancelled(let at) = $0 { at } else { nil }
    }
  }
}
