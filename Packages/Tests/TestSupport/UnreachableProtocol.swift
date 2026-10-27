import Foundation
import Synchronization

/// Refuses every request at once, so going offline depends on nothing outside the test.
public final class UnreachableProtocol: URLProtocol {
  /// Every path refused, with the seconds since the first, for the failure message.
  public static let seen = Mutex<[String]>([])
  static let started = Mutex<Date?>(nil)

  /// A session routed here, with the record of refusals cleared.
  public static func session() -> URLSession {
    seen.withLock { $0 = [] }
    started.withLock { $0 = nil }
    return .stubbed(by: UnreachableProtocol.self)
  }

  override public class func canInit(with request: URLRequest) -> Bool { true }
  override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override public func startLoading() {
    let now = Date()
    let first = Self.started.withLock { started -> Date in
      if let started { return started }
      started = now
      return now
    }
    let path = request.url?.path ?? "?"
    Self.seen.withLock {
      $0.append("\(path)@\(String(format: "%.2f", now.timeIntervalSince(first)))s")
    }
    client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
  }

  override public func stopLoading() {}
}
