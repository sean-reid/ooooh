import Foundation

/// Any clock, read as the offset since it was wrapped, so tests drive timers with a clock they advance by hand.
public struct OffsetClock: Sendable {
  public let now: @Sendable () -> Duration
  public let sleep: @Sendable (Duration) async throws -> Void

  public init<C: Clock>(_ clock: C) where C.Duration == Duration {
    let origin = clock.now
    now = { origin.duration(to: clock.now) }
    sleep = { try await clock.sleep(until: origin.advanced(by: $0), tolerance: nil) }
  }
}
