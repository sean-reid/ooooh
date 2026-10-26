import Foundation
import Testing

@testable import Proxy

extension StubbedTransportTests {
  @Suite struct SessionStartTests {
    let client: ProxyClient = {
      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [StubProtocol.self]
      return ProxyClient(
        baseURL: URL(string: "https://ooooh.test")!, session: URLSession(configuration: config))
    }()

    func fixture(_ name: String) throws -> Data {
      let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
      return try Data(contentsOf: url)
    }

    @Test func postsTheStartAndDecodesAFreeSession() async throws {
      StubProtocol.reply = .init(status: 200, chunks: [try fixture("session-start-free")])
      StubProtocol.seen.withLock { $0 = [] }

      let start = try await client.startSession()
      #expect(start == .free(remaining: 2, promptMinutes: 20))

      let request = try #require(StubProtocol.seen.withLock { $0.first })
      #expect(request.url?.path() == "/v1/session/start")
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func decodesAPaidSession() async throws {
      StubProtocol.reply = .init(status: 200, chunks: [try fixture("session-start-paid")])
      StubProtocol.seen.withLock { $0 = [] }
      #expect(try await client.startSession() == .paid)
    }

    @Test func decodesARefusal() async throws {
      StubProtocol.reply = .init(status: 200, chunks: [try fixture("session-start-refused")])
      StubProtocol.seen.withLock { $0 = [] }
      #expect(try await client.startSession() == .refused(reason: "free-exhausted"))
    }

    @Test func postsTheMinutesAtTheEndAndAcceptsNoContent() async throws {
      StubProtocol.reply = .init(status: 204, chunks: [])
      StubProtocol.seen.withLock { $0 = [] }

      try await client.endSession(minutes: 12.5)

      let request = try #require(StubProtocol.seen.withLock { $0.first })
      #expect(request.url?.path() == "/v1/session/end")
      #expect(request.httpMethod == "POST")
      let body = try JSONSerialization.jsonObject(with: request.bodyBytes) as? [String: Double]
      #expect(body == ["minutes": 12.5])
    }

    @Test func aNoSessionAnswerIsItsOwnError() async throws {
      StubProtocol.reply = .init(
        status: 402, chunks: [Data(#"{"error":"no-session","reason":"minutes-used"}"#.utf8)])
      StubProtocol.seen.withLock { $0 = [] }
      await #expect(throws: ProxyError.noSession(reason: "minutes-used")) {
        try await client.endSession(minutes: 1)
      }
    }

    @Test func anotherPaymentRequiredBodyKeepsItsStatus() async throws {
      StubProtocol.reply = .init(status: 402, chunks: [Data(#"{"error":"other"}"#.utf8)])
      StubProtocol.seen.withLock { $0 = [] }
      await #expect(throws: ProxyError.status(402, body: #"{"error":"other"}"#)) {
        try await client.endSession(minutes: 1)
      }
    }

    @Test func surfacesAWorkerError() async throws {
      StubProtocol.reply = .init(
        status: 422, chunks: [Data(#"{"error":"invalid","reason":"minutes"}"#.utf8)])
      StubProtocol.seen.withLock { $0 = [] }
      await #expect(throws: ProxyError.self) { try await client.endSession(minutes: 1) }
    }
  }
}
