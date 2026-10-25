import Foundation
import Synchronization

/// Reachability of the Worker as the client experiences it: offline after
/// `failuresToTrip` consecutive transport failures, online again on one success.
/// While offline, one probe per `retryInterval` is allowed through.
public final class OfflineGuard: Sendable {
  public let failuresToTrip: Int
  public let retryInterval: TimeInterval

  private struct Storage {
    var failures = 0
    var isOffline = false
    var lastProbe: Date?
    var subscribers: [UUID: AsyncStream<Bool>.Continuation] = [:]
  }

  private let storage: Mutex<Storage>

  public init(failuresToTrip: Int = 2, retryInterval: TimeInterval = 10, offline: Bool = false) {
    self.failuresToTrip = failuresToTrip
    self.retryInterval = retryInterval
    storage = Mutex(Storage(isOffline: offline))
  }

  public var isOffline: Bool { storage.withLock { $0.isOffline } }

  /// Every change, after the current value.
  public func changes() -> AsyncStream<Bool> {
    let id = UUID()
    return AsyncStream { continuation in
      storage.withLock { $0.subscribers[id] = continuation }
      continuation.onTermination = { [weak self] _ in self?.unsubscribe(id) }
    }
  }

  /// True when a request may go out: always while online, once per interval while offline.
  public func allowsRequest(now: Date = .now) -> Bool {
    storage.withLock { state in
      guard state.isOffline else { return true }
      if let last = state.lastProbe, now.timeIntervalSince(last) < retryInterval { return false }
      state.lastProbe = now
      return true
    }
  }

  public func recordSuccess() {
    publish(
      storage.withLock { state in
        state.failures = 0
        state.lastProbe = nil
        guard state.isOffline else { return nil }
        state.isOffline = false
        return Array(state.subscribers.values)
      }, false)
  }

  public func recordFailure(_ error: any Error) {
    if let urlError = error as? URLError, urlError.code == .cancelled { return }
    publish(
      storage.withLock { state in
        state.failures += 1
        guard !state.isOffline, state.failures >= failuresToTrip else { return nil }
        state.isOffline = true
        return Array(state.subscribers.values)
      }, true)
  }

  private func unsubscribe(_ id: UUID) {
    _ = storage.withLock { $0.subscribers.removeValue(forKey: id) }
  }

  private func publish(_ subscribers: [AsyncStream<Bool>.Continuation]?, _ value: Bool) {
    for subscriber in subscribers ?? [] { subscriber.yield(value) }
  }
}
