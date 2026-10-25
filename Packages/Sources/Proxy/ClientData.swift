import CryptoKit
import Foundation

/// What one assertion covers, in the form the Worker rebuilds from the request it receives.
public struct ClientData: Sendable, Equatable {
  /// The header that carries `time`, so the Worker can rebuild the string and refuse a stale one.
  public static let timeHeader = "x-assertion-time"

  public var method: String
  public var path: String
  /// Unix seconds when the request was signed.
  public var time: Int
  /// SHA256 of the body bytes.
  public var bodyHash: Data

  public init(method: String, path: String, time: Int, bodyHash: Data) {
    self.method = method
    self.path = path
    self.time = time
    self.bodyHash = bodyHash
  }

  /// Method, path, seconds, and the hex body hash, newline separated.
  public var canonical: String {
    [method, path, String(time), Self.hex(bodyHash)].joined(separator: "\n")
  }

  /// SHA256 of `canonical`, the `clientDataHash` handed to App Attest.
  public var hash: Data { Data(SHA256.hash(data: Data(canonical.utf8))) }

  static func hex(_ bytes: Data) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
  }
}
