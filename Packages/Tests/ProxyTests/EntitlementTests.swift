import Foundation
import Testing

@testable import Proxy

extension StubbedTransportTests {
  @Suite struct EntitlementTests {
    let client: ProxyClient = {
      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [StubProtocol.self]
      return ProxyClient(
        baseURL: URL(string: "https://ooooh.test")!, session: URLSession(configuration: config))
    }()

    let jws = "eyJhbGciOiJFUzI1NiJ9.eyJwcm9kdWN0SWQiOiJtb250aGx5In0.c2ln"

    @Test func postsTheTransactionAndDecodesAPaidAnswer() async throws {
      StubProtocol.reply = .init(
        status: 200,
        chunks: [Data(#"{"entitlement":"paid","expiresDate":1766656800000}"#.utf8)])
      StubProtocol.seen.withLock { $0 = [] }

      let response = try await client.submitEntitlement(transactionJWS: jws)
      #expect(
        response
          == EntitlementResponse(
            entitlement: .paid, expiresDate: Date(timeIntervalSince1970: 1_766_656_800)))

      let request = try #require(StubProtocol.seen.withLock { $0.first })
      #expect(request.url?.path() == "/v1/entitlement")
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
      let body = try JSONSerialization.jsonObject(with: request.bodyBytes) as? [String: String]
      #expect(body == ["transaction": jws])
    }

    @Test func decodesAFreeAnswerWithoutAnExpiry() async throws {
      StubProtocol.reply = .init(
        status: 200, chunks: [Data(#"{"entitlement":"free","expiresDate":null}"#.utf8)])
      StubProtocol.seen.withLock { $0 = [] }

      let response = try await client.submitEntitlement(transactionJWS: jws)
      #expect(response == EntitlementResponse(entitlement: .free))
    }

    @Test func surfacesTheWorkerRefusal() async throws {
      StubProtocol.reply = .init(
        status: 401,
        chunks: [Data(#"{"error":"unauthorized","reason":"bad-transaction"}"#.utf8)])
      StubProtocol.seen.withLock { $0 = [] }

      await #expect(throws: ProxyError.self) {
        try await client.submitEntitlement(transactionJWS: jws)
      }
    }
  }
}
