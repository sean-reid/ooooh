import Billing
import Observation
import Proxy

/// The Worker's latest word on the free count, kept for this launch. Sessions write it as they
/// start and the billing store reads it.
@MainActor @Observable
final class FreeSessions: FreeSessionCount {
  private(set) var remaining: Int?

  nonisolated var remainingFreeSessions: Int? {
    get async { await remaining }
  }

  func record(_ start: SessionStart) {
    switch start {
    case .free(let remaining, _): self.remaining = remaining
    case .refused: remaining = 0
    case .paid: break
    }
  }
}
