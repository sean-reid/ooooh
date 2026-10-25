import Foundation
import Governor
import State
import Transcription

/// Everything the loop did, in order, with the fixture clock. The eval reads these.
public enum SessionRecord: Equatable, Sendable {
  case check(at: TimeInterval, index: Int, answers: JevAnswers, decision: Decision)
  case prompt(at: TimeInterval, kind: InterventionKind, text: String)
  case askedIfFinished(at: TimeInterval)
  case command(at: TimeInterval, JevAnswers.Command)
  case compaction(at: TimeInterval, patch: StatePatch)
  case compactionRejected(at: TimeInterval, reason: String)
  case ended(at: TimeInterval, byUser: Bool)

  public var at: TimeInterval {
    switch self {
    case .check(let at, _, _, _), .prompt(let at, _, _), .askedIfFinished(let at),
      .command(let at, _), .compaction(let at, _), .compactionRejected(let at, _),
      .ended(let at, _):
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

  public var finishedAsks: [TimeInterval] {
    records.compactMap {
      if case .askedIfFinished(let at) = $0 { at } else { nil }
    }
  }
}
