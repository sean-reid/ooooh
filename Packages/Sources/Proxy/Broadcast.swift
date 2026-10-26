import Foundation
import Synchronization

/// Hands every published value to the streams open at the time.
final class Broadcast<Value: Sendable>: Sendable {
  private let subscribers = Mutex<[UUID: AsyncStream<Value>.Continuation]>([:])

  func changes() -> AsyncStream<Value> {
    let id = UUID()
    return AsyncStream { continuation in
      subscribers.withLock { $0[id] = continuation }
      continuation.onTermination = { [weak self] _ in
        _ = self?.subscribers.withLock { $0.removeValue(forKey: id) }
      }
    }
  }

  func publish(_ value: Value) {
    for subscriber in subscribers.withLock({ Array($0.values) }) { subscriber.yield(value) }
  }
}
