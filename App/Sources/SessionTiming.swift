import Foundation

/// The session's clock: Start to End, less every pause. The elapsed time on screen, the saved
/// duration, and the minutes posted to the Worker all read it.
struct SessionTiming {
  private(set) var startedAt: Date?
  private(set) var endedAt: Date?
  private(set) var pausedAt: Date?
  private var pausedBefore: TimeInterval = 0

  var isPaused: Bool { pausedAt != nil }

  mutating func start(at now: Date) {
    startedAt = now
    endedAt = nil
    pausedAt = nil
    pausedBefore = 0
  }

  mutating func pause(at now: Date) {
    guard startedAt != nil, endedAt == nil, pausedAt == nil else { return }
    pausedAt = now
  }

  mutating func resume(at now: Date) {
    guard let pausedAt else { return }
    pausedBefore += max(0, now.timeIntervalSince(pausedAt))
    self.pausedAt = nil
  }

  /// The first End wins; a pause still open closes with it.
  mutating func end(at now: Date) {
    guard startedAt != nil, endedAt == nil else { return }
    resume(at: now)
    endedAt = now
  }

  func elapsed(at now: Date) -> TimeInterval {
    guard let startedAt else { return 0 }
    let until = endedAt ?? now
    let open = pausedAt.map { max(0, until.timeIntervalSince($0)) } ?? 0
    return max(0, until.timeIntervalSince(startedAt) - pausedBefore - open)
  }
}
