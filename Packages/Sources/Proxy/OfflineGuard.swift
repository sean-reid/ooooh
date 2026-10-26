import Foundation
import OSLog
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
  }

  private let storage: Mutex<Storage>
  private let broadcast = Broadcast<Bool>()

  public init(failuresToTrip: Int = 2, retryInterval: TimeInterval = 10, offline: Bool = false) {
    self.failuresToTrip = failuresToTrip
    self.retryInterval = retryInterval
    storage = Mutex(Storage(isOffline: offline))
  }

  public var isOffline: Bool { storage.withLock { $0.isOffline } }

  /// Every change, after the current value.
  public func changes() -> AsyncStream<Bool> { broadcast.changes() }

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
    let cameBack = storage.withLock { state in
      state.failures = 0
      state.lastProbe = nil
      guard state.isOffline else { return false }
      state.isOffline = false
      return true
    }
    if cameBack {
      proxyLog.info("worker back")
      broadcast.publish(false)
    }
  }

  public func recordFailure(_ error: any Error) {
    if let urlError = error as? URLError, urlError.code == .cancelled { return }
    let tripped = storage.withLock { state in
      state.failures += 1
      guard !state.isOffline, state.failures >= failuresToTrip else { return false }
      state.isOffline = true
      return true
    }
    if tripped {
      proxyLog.error("worker offline after \(self.failuresToTrip, privacy: .public) failures")
      broadcast.publish(true)
    }
  }
}
