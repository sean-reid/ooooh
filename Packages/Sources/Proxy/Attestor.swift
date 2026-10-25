import Foundation

/// One App Attest assertion: the key it came from and the CBOR the Worker verifies.
public struct Assertion: Sendable, Equatable {
  public var keyId: String
  public var assertion: Data

  public init(keyId: String, assertion: Data) {
    self.keyId = keyId
    self.assertion = assertion
  }
}

/// Proves a request came from this install. `bodyHash` is SHA256 of the bytes being sent.
public protocol Attestor: Sendable {
  /// Nil means the request goes out with no attestation headers.
  func assertion(bodyHash: Data) async throws -> Assertion?
}

/// App Attest does not run on the simulator; the Worker there has `REQUIRE_ATTESTATION=false`.
public struct SimulatorAttestor: Attestor {
  public init() {}

  public func assertion(bodyHash: Data) async throws -> Assertion? { nil }
}

/// The two wire shapes shared with the Worker's `/v1/challenge` and `/v1/attest`.
struct ChallengeResponse: Decodable {
  var challenge: String
}

struct AttestBody: Encodable {
  var keyId: String
  var attestation: String
  var challenge: String
}
