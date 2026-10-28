import Foundation
import Synchronization

/// The Worker's clock as the client learned it from a stale 401: the signed offset every later
/// request is signed with, for the rest of the process, and whether the Worker refused the time
/// again once the offset was applied.
public final class WorkerClock: Sendable {
  /// Every client in the process signs with this one unless given another.
  public static let shared = WorkerClock()

  private struct Storage {
    var offset = 0
    var isRefused = false
  }

  private let storage = Mutex(Storage())
  private let broadcast = Broadcast<Bool>()
  private let deviceNow: @Sendable () -> Date

  /// `now` is the device clock; tests pass a fixed one so the learned offset is exact.
  public init(now: @escaping @Sendable () -> Date = { .now }) {
    deviceNow = now
  }

  /// Server time minus device time in whole seconds. Zero until a stale 401 carries a Date.
  public var offset: Int { storage.withLock { $0.offset } }

  /// True after the Worker refused a time signed with the learned offset, until it accepts one.
  public var isRefused: Bool { storage.withLock { $0.isRefused } }

  /// Every change of `isRefused`, after the current value.
  public func changes() -> AsyncStream<Bool> { broadcast.changes() }

  /// The unix seconds to sign a request with: the device's now, by the Worker's clock.
  public func now(_ device: Date? = nil) -> Int {
    Int((device ?? deviceNow()).timeIntervalSince1970) + offset
  }

  func learn(serverTime: Date, at device: Date? = nil) {
    let device = device ?? deviceNow()
    storage.withLock { $0.offset = Int(serverTime.timeIntervalSince(device).rounded()) }
  }

  func recordRefused() { record(refused: true) }

  func recordAccepted() { record(refused: false) }

  private func record(refused: Bool) {
    let changed = storage.withLock { state in
      guard state.isRefused != refused else { return false }
      state.isRefused = refused
      return true
    }
    if changed { broadcast.publish(refused) }
  }

  /// A `Date` header, such as `Sun, 06 Nov 1994 08:49:37 GMT`.
  static func httpDate(_ header: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.date(from: header)
  }
}
