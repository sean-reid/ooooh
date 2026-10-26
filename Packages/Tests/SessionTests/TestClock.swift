import Foundation

/// A clock the test advances by hand, so timing tests never read the wall clock.
final class TestClock: Clock, @unchecked Sendable {
  struct Instant: InstantProtocol {
    var offset: Duration

    func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
    func duration(to other: Instant) -> Duration { other.offset - offset }
    static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
  }

  private struct Waiter {
    let id: UUID
    let deadline: Instant
    let continuation: CheckedContinuation<Void, any Error>
  }

  private let lock = NSLock()
  private var current = Instant(offset: .zero)
  private var waiters: [Waiter] = []

  var now: Instant { lock.withLock { current } }
  var minimumResolution: Duration { .zero }

  /// How many sleepers are parked, which a test reads to know the stream has caught up.
  var sleeping: Int { lock.withLock { waiters.count } }

  /// When each parked sleeper wakes, as offsets from zero.
  var deadlines: [Duration] { lock.withLock { waiters.map(\.deadline.offset) } }

  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    if deadline <= now { return }
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let cancelled = lock.withLock {
          if Task.isCancelled { return true }
          waiters.append(Waiter(id: id, deadline: deadline, continuation: continuation))
          return false
        }
        if cancelled { continuation.resume(throwing: CancellationError()) }
      }
    } onCancel: {
      let waiter = lock.withLock {
        let waiter = waiters.first { $0.id == id }
        waiters.removeAll { $0.id == id }
        return waiter
      }
      waiter?.continuation.resume(throwing: CancellationError())
    }
  }

  func advance(to instant: Instant) {
    let due = lock.withLock {
      current = instant
      let due = waiters.filter { $0.deadline <= instant }
      waiters.removeAll { $0.deadline <= instant }
      return due
    }
    for waiter in due { waiter.continuation.resume() }
  }

  func advance(by duration: Duration) { advance(to: now.advanced(by: duration)) }
}
