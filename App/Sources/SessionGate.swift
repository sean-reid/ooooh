import Governor
import Proxy
import Session

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
}

/// Applies the Worker's answer to every decision: quiet once refused or past the free prompt
/// minutes, the real provider otherwise. A check that comes before the answer waits for it.
struct AdmittedDecisions: DecisionProvider {
  let base: any DecisionProvider
  let admission: Task<SessionStart?, Never>

  func check(_ input: CheckInput) async throws -> JevAnswers {
    switch await admission.value {
    case .refused:
      return .quiet
    case .free(_, let promptMinutes) where input.signals.now >= Double(promptMinutes) * 60:
      return .quiet
    case .free, .paid, nil:
      return try await base.check(input)
    }
  }
}
