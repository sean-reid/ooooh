import Foundation

/// What `POST /v1/entitlement` answers once the Worker has verified a StoreKit 2 transaction.
public struct EntitlementResponse: Decodable, Equatable, Sendable {
  public enum Entitlement: String, Decodable, Sendable {
    case free
    case paid
  }

  public var entitlement: Entitlement
  /// Absent when the transaction carries no expiry.
  public var expiresDate: Date?

  public init(entitlement: Entitlement, expiresDate: Date? = nil) {
    self.entitlement = entitlement
    self.expiresDate = expiresDate
  }
}

extension ProxyClient {
  struct EntitlementBody: Encodable {
    var transaction: String
  }

  /// Posts the latest signed transaction. The Worker answers in milliseconds since 1970.
  public func submitEntitlement(transactionJWS: String) async throws -> EntitlementResponse {
    let request = try await request(
      "v1/entitlement", body: EntitlementBody(transaction: transactionJWS))
    let (data, response) = try await transport { try await session.data(for: request) }
    try ProxyError.check(response, data: data)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return try decoder.decode(EntitlementResponse.self, from: data)
  }
}
