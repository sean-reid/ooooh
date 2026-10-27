import Foundation
import TestSupport
import Testing

@testable import Proxy

extension StubbedTransportTests {
  @Suite struct EntitlementTests {
    let client = ProxyClient(
      baseURL: URL(string: "https://ooooh.test")!, session: StubProtocol.session())

    let jws = "eyJhbGciOiJFUzI1NiJ9.eyJwcm9kdWN0SWQiOiJtb250aGx5In0.c2ln"

    @Test func postsTheTransactionAndDecodesAPaidAnswer() async throws {
      StubProtocol.reply = .init(
        status: 200, chunks: [try Bundle.module.fixture("entitlement-paid.json")])
      StubProtocol.reset()

      let response = try await client.submitEntitlement(transactionJWS: jws)
      #expect(
        response
          == EntitlementResponse(
            entitlement: .paid, expiresDate: Date(timeIntervalSince1970: 4_070_908_800)))

      let request = try #require(StubProtocol.seen.withLock { $0.first })
      #expect(request.url?.path() == "/v1/entitlement")
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
      let body = try JSONSerialization.jsonObject(with: request.bodyBytes) as? [String: String]
      #expect(body == ["transaction": jws])
    }

    @Test func decodesAFreeAnswerWithTheExpiryThatPassed() async throws {
      StubProtocol.reply = .init(
        status: 200, chunks: [try Bundle.module.fixture("entitlement-free.json")])
      StubProtocol.reset()

      let response = try await client.submitEntitlement(transactionJWS: jws)
      #expect(
        response
          == EntitlementResponse(
            entitlement: .free, expiresDate: Date(timeIntervalSince1970: 1_780_272_000)))
    }

    @Test func decodesAFreeAnswerWithoutAnExpiry() async throws {
      StubProtocol.reply = .init(
        status: 200, chunks: [Data(#"{"entitlement":"free","expiresDate":null}"#.utf8)])
      StubProtocol.reset()

      let response = try await client.submitEntitlement(transactionJWS: jws)
      #expect(response == EntitlementResponse(entitlement: .free))
    }

    @Test func aRefusalCarriesTheWorkersReason() async throws {
      StubProtocol.reply = .init(
        status: 401, chunks: [try Bundle.module.fixture("entitlement-refused.json")])
      StubProtocol.reset()

      await #expect(throws: ProxyError.unauthorized(reason: "wrong-device")) {
        try await client.submitEntitlement(transactionJWS: jws)
      }
    }

    @Test func anotherUnauthorizedBodyKeepsItsStatus() async throws {
      StubProtocol.reply = .init(status: 401, chunks: [Data(#"{"error":"other"}"#.utf8)])
      StubProtocol.reset()

      await #expect(throws: ProxyError.status(401, body: #"{"error":"other"}"#)) {
        try await client.submitEntitlement(transactionJWS: jws)
      }
    }
  }
}
