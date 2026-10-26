import DeviceCheck
import Foundation

/// The three App Attest calls, so the attestor runs against a fake in tests.
protocol AppAttestService: Sendable {
  func generateKey() async throws -> String
  func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
  func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

extension DCAppAttestService: AppAttestService {}

extension ProxyError {
  /// `featureUnsupported` and `invalidInput` do not change with a retry; the rest may.
  init(_ error: DCError) {
    switch error.code {
    case .featureUnsupported: self = .cannotAttest("feature-unsupported")
    case .invalidInput: self = .cannotAttest("invalid-input")
    case .invalidKey: self = .attestation("invalid-key")
    case .serverUnavailable: self = .attestation("server-unavailable")
    case .unknownSystemFailure: self = .attestation("system-failure")
    @unknown default: self = .attestation("dcerror-\(error.code.rawValue)")
    }
  }
}
