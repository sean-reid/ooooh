import Proxy

/// Posts one signed transaction to the Worker. A closure, so the store runs without a Worker in tests.
public struct EntitlementPoster: Sendable {
  public var post: @Sendable (_ transactionJWS: String) async throws -> EntitlementResponse

  public init(post: @escaping @Sendable (String) async throws -> EntitlementResponse) {
    self.post = post
  }

  public static func worker(_ client: ProxyClient) -> EntitlementPoster {
    EntitlementPoster { try await client.submitEntitlement(transactionJWS: $0) }
  }
}
