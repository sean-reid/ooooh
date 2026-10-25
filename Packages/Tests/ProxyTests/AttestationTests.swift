import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import Proxy

/// Records the hash it was asked to sign and answers with a fixed assertion, or nothing.
final class FakeAttestor: Attestor {
  let hashes = Mutex<[Data]>([])
  let reply: Assertion?

  init(reply: Assertion?) {
    self.reply = reply
  }

  func assertion(bodyHash: Data) async throws -> Assertion? {
    hashes.withLock { $0.append(bodyHash) }
    return reply
  }
}

extension StubbedTransportTests {
  @Suite struct AttestationTests {
    func client(_ attestor: any Attestor) -> ProxyClient {
      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [StubProtocol.self]
      return ProxyClient(
        baseURL: URL(string: "https://ooooh.test")!, session: URLSession(configuration: config),
        attestor: attestor)
    }

    @Test func signsTheExactBodyBytesAndSendsBothHeaders() async throws {
      let attestor = FakeAttestor(
        reply: Assertion(keyId: "key-1", assertion: Data([0xa2, 0x01, 0x02])))
      StubProtocol.reply = .init(status: 200, chunks: [Data(#"{"text":"Which part?"}"#.utf8)])
      StubProtocol.seen.withLock { $0 = [] }

      let response: SonnetPhraser.Response = try await client(attestor).post(
        "v1/phrase", body: ["kind": "clarify"])
      #expect(response.text == "Which part?")

      let request = try #require(StubProtocol.seen.withLock { $0.first })
      #expect(request.value(forHTTPHeaderField: "x-device") == "key-1")
      #expect(request.value(forHTTPHeaderField: "x-assertion") == "ogEC")
      #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
      let hashes = attestor.hashes.withLock { $0 }
      #expect(hashes == [Data(SHA256.hash(data: request.bodyBytes))])
    }

    @Test func sendsNoAttestationHeadersWhenTheAttestorHasNone() async throws {
      let attestor = FakeAttestor(reply: nil)
      StubProtocol.reply = .init(status: 200, chunks: [Data(#"{"text":"Which part?"}"#.utf8)])
      StubProtocol.seen.withLock { $0 = [] }

      let _: SonnetPhraser.Response = try await client(attestor).post(
        "v1/phrase", body: ["kind": "clarify"])

      let request = try #require(StubProtocol.seen.withLock { $0.first })
      #expect(request.value(forHTTPHeaderField: "x-device") == nil)
      #expect(request.value(forHTTPHeaderField: "x-assertion") == nil)
      #expect(attestor.hashes.withLock { $0.count } == 1)
    }

    @Test func simulatorAttestorSignsNothing() async throws {
      #expect(try await SimulatorAttestor().assertion(bodyHash: Data(count: 32)) == nil)
    }

    @Test func attestBodyUsesTheWorkerFieldNames() throws {
      let body = AttestBody(keyId: "k", attestation: "YQ==", challenge: "Yg==")
      let json =
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: String]
      #expect(json == ["keyId": "k", "attestation": "YQ==", "challenge": "Yg=="])
      let challenge = try JSONDecoder().decode(
        ChallengeResponse.self, from: Data(#"{"challenge":"Yg=="}"#.utf8))
      #expect(challenge.challenge == "Yg==")
    }
  }
}
