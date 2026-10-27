import Foundation
import Governor
import State
import Transcription

/// Everything a decision needs. Built by the loop, sent to Jev or a fake.
public struct CheckInput: Equatable, Sendable {
  public var state: CompactState
  public var recentTranscript: [Segment]
  public var signals: Signals
  public var checkIndex: Int

  public init(state: CompactState, recentTranscript: [Segment], signals: Signals, checkIndex: Int) {
    self.state = state
    self.recentTranscript = recentTranscript
    self.signals = signals
    self.checkIndex = checkIndex
  }
}

public protocol DecisionProvider: Sendable {
  func check(_ input: CheckInput) async throws -> JevAnswers
}

public protocol Compactor: Sendable {
  func compact(state: CompactState, transcript: [Segment]) async throws -> StatePatch
}

public protocol Phraser: Sendable {
  /// `said` is the last few lines the app spoke this session, oldest first.
  func phrase(
    _ kind: InterventionKind, state: CompactState, recent: [Segment],
    said: [CompactState.Intervention]
  ) async throws -> String
}

/// Answers from a closure. Tests script the moments they want.
public struct ScriptedDecisionProvider: DecisionProvider {
  let script: @Sendable (CheckInput) -> JevAnswers

  public init(_ script: @escaping @Sendable (CheckInput) -> JevAnswers) {
    self.script = script
  }

  public func check(_ input: CheckInput) async throws -> JevAnswers {
    script(input)
  }
}

/// Never asks for anything.
public struct SilentDecisionProvider: DecisionProvider {
  public init() {}

  public func check(_ input: CheckInput) async throws -> JevAnswers {
    .quiet
  }
}

/// Folds the new transcript into the thread without any model.
public struct PassthroughCompactor: Compactor {
  public init() {}

  public func compact(state: CompactState, transcript: [Segment]) async throws -> StatePatch {
    let tail = transcript.suffix(3).map(\.text).joined(separator: " ")
    return StatePatch(currentThread: String(tail.suffix(200)))
  }
}

/// One fixed line per kind. Stands in for Sonnet in fixtures and tests.
public struct TemplatePhraser: Phraser {
  public init() {}

  public func phrase(
    _ kind: InterventionKind, state: CompactState, recent: [Segment],
    said: [CompactState.Intervention]
  ) async throws -> String {
    switch kind {
    case .clarify: "Which part of that feels least clear?"
    case .deepen: "What sits underneath that?"
    case .reflect: "That came up twice now."
    case .decide: "Does that settle it?"
    case .summarize: "So far: \(state.currentThread.prefix(80))"
    case .challenge: "What would make that wrong?"
    }
  }
}

extension JevAnswers {
  /// Flowing speech, no signal to act on.
  public static let quiet = JevAnswers(
    goodMoment: .init(0.05),
    intervention: .init(.clarify, confidence: 0.1),
    articulationDifficulty: .init(1, confidence: 0.8),
    momentum: .init(5, confidence: 0.8),
    seemsFinished: .init(0.02),
    addressesApp: .init(.none, confidence: 0.05))
}

/// Asks one compactor and, when it throws, the other.
public struct FallbackCompactor: Compactor {
  public var primary: any Compactor
  public var fallback: any Compactor

  public init(primary: any Compactor, fallback: any Compactor) {
    self.primary = primary
    self.fallback = fallback
  }

  public func compact(state: CompactState, transcript: [Segment]) async throws -> StatePatch {
    do {
      return try await primary.compact(state: state, transcript: transcript)
    } catch {
      return try await fallback.compact(state: state, transcript: transcript)
    }
  }
}
