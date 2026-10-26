import Foundation
import Governor
import Proxy
import Session
import State
import Synchronization
import Transcription

/// The Worker's say on one session: free, paid, or without prompts, and the minutes it used at
/// the end. Closures, so tests and `-free-exhausted 1` answer by hand.
struct SessionGate: Sendable {
  var start: @Sendable () async throws -> SessionStart
  var end: @Sendable (_ minutes: Double) async throws -> Void

  static func worker(_ client: ProxyClient) -> SessionGate {
    SessionGate(
      start: { try await client.startSession() },
      end: { try await client.endSession(minutes: $0) })
  }

  /// Answers as the Worker does once the month's free sessions are used.
  static let exhausted = SessionGate(
    start: { .refused(reason: "free-exhausted") }, end: { _ in })

  /// Minutes as the end route reads them, to the hundredth.
  static func minutes(_ seconds: TimeInterval) -> Double {
    (seconds / 60 * 100).rounded() / 100
  }
}

/// The Worker's say on one session as it stands: the start answer once it arrives, and the
/// reason of the first 402 a later call answered.
final class Admission: Sendable {
  let start: Task<SessionStart?, Never>
  private let cutoff = Mutex<String?>(nil)
  private let onCutoff: @Sendable (String) -> Void

  init(start: Task<SessionStart?, Never>, onCutoff: @escaping @Sendable (String) -> Void) {
    self.start = start
    self.onCutoff = onCutoff
  }

  var startRefused: Bool {
    get async {
      if case .refused = await start.value { return true }
      return false
    }
  }

  /// Decisions, phrasing, and compaction that follow the Worker's answer.
  func wrap(_ dependencies: SessionLoop.Dependencies) -> SessionLoop.Dependencies {
    SessionLoop.Dependencies(
      decisions: Decisions(base: dependencies.decisions, admission: self),
      compactor: Compacting(base: dependencies.compactor, admission: self),
      phraser: Phrasing(base: dependencies.phraser, admission: self))
  }

  /// Runs `call` while the Worker admits this session. After a refusal, at the start or as a
  /// 402 from any call, `fallback` answers instead.
  func admit<T>(_ call: () async throws -> T, refused fallback: @autoclosure () -> T)
    async throws -> T
  {
    if cutoff.withLock({ $0 }) != nil { return fallback() }
    if await startRefused { return fallback() }
    do {
      return try await call()
    } catch ProxyError.noSession(let reason) {
      record(reason)
      return fallback()
    }
  }

  /// The Worker's audio as it streams, with a 402 recorded like any other call's.
  func admit(_ audio: AsyncThrowingStream<Data, Error>) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await chunk in audio { continuation.yield(chunk) }
          continuation.finish()
        } catch {
          if case ProxyError.noSession(let reason) = error { record(reason) }
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func record(_ reason: String) {
    let first = cutoff.withLock { recorded in
      guard recorded == nil else { return false }
      recorded = reason
      return true
    }
    if first { onCutoff(reason) }
  }

  /// Quiet once refused or past the free prompt minutes, Jev otherwise. A check that comes
  /// before the start answer waits for it.
  private struct Decisions: DecisionProvider {
    let base: any DecisionProvider
    let admission: Admission

    func check(_ input: CheckInput) async throws -> JevAnswers {
      if case .free(_, let promptMinutes)? = await admission.start.value,
        input.signals.now >= Double(promptMinutes) * 60
      {
        return .quiet
      }
      return try await admission.admit({ try await base.check(input) }, refused: .quiet)
    }
  }

  /// Sonnet until refused, then nothing to say.
  private struct Phrasing: Phraser {
    let base: any Phraser
    let admission: Admission

    func phrase(_ kind: InterventionKind, state: CompactState, recent: [Segment]) async throws
      -> String
    {
      try await admission.admit(
        { try await base.phrase(kind, state: state, recent: recent) }, refused: "")
    }
  }

  /// Haiku for an admitted session; a refused one folds the transcript locally and asks nothing.
  /// Compaction keeps running past the prompt minutes, as the Worker does.
  private struct Compacting: Compactor {
    let base: any Compactor
    let admission: Admission

    func compact(state: CompactState, transcript: [Segment]) async throws -> StatePatch {
      let refused = await admission.startRefused
      let compactor: any Compactor = refused ? PassthroughCompactor() : base
      return try await compactor.compact(state: state, transcript: transcript)
    }
  }
}
