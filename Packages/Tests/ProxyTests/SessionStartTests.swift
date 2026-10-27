import Foundation
import TestSupport
import Testing

@testable import Proxy

extension StubbedTransportTests {
  @Suite struct SessionStartTests {
    let client = ProxyClient(
      baseURL: URL(string: "https://ooooh.test")!, session: StubProtocol.session())

    @Test func postsTheStartAndDecodesAFreeSession() async throws {
      StubProtocol.reply = .init(
        status: 200, chunks: [try Bundle.module.fixture("session-start-free.json")])
      StubProtocol.reset()

      let start = try await client.startSession()
      #expect(start == .free(remaining: 2, promptMinutes: 20))

      let request = try #require(StubProtocol.seen.withLock { $0.first })
      #expect(request.url?.path() == "/v1/session/start")
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func decodesAPaidSession() async throws {
      StubProtocol.reply = .init(
        status: 200, chunks: [try Bundle.module.fixture("session-start-paid.json")])
      StubProtocol.reset()
      #expect(try await client.startSession() == .paid)
    }

    @Test func decodesARefusal() async throws {
      StubProtocol.reply = .init(
        status: 200, chunks: [try Bundle.module.fixture("session-start-refused.json")])
      StubProtocol.reset()
      #expect(try await client.startSession() == .refused(reason: "free-exhausted"))
    }

    @Test func postsTheMinutesAtTheEndAndAcceptsNoContent() async throws {
      StubProtocol.reply = .init(status: 204, chunks: [])
      StubProtocol.reset()

      try await client.endSession(minutes: 12.5)

      let request = try #require(StubProtocol.seen.withLock { $0.first })
      #expect(request.url?.path() == "/v1/session/end")
      #expect(request.httpMethod == "POST")
      let body = try JSONSerialization.jsonObject(with: request.bodyBytes) as? [String: Double]
      #expect(body == ["minutes": 12.5])
    }

    /// The three 402 bodies the Worker's session check answers, written by its node project.
    @Test(arguments: ["not-started", "free-used", "minutes-used"])
    func aNoSessionAnswerIsItsOwnError(reason: String) async throws {
      StubProtocol.reply = .init(
        status: 402, chunks: [try Bundle.module.fixture("no-session-\(reason).json")])
      StubProtocol.reset()
      await #expect(throws: ProxyError.noSession(reason: reason)) {
        try await client.endSession(minutes: 1)
      }
    }

    @Test func anotherPaymentRequiredBodyKeepsItsStatus() async throws {
      StubProtocol.reply = .init(status: 402, chunks: [Data(#"{"error":"other"}"#.utf8)])
      StubProtocol.reset()
      await #expect(throws: ProxyError.status(402, body: #"{"error":"other"}"#)) {
        try await client.endSession(minutes: 1)
      }
    }

    @Test func surfacesAWorkerError() async throws {
      StubProtocol.reply = .init(
        status: 422, chunks: [Data(#"{"error":"invalid","reason":"minutes"}"#.utf8)])
      StubProtocol.reset()
      await #expect(throws: ProxyError.self) { try await client.endSession(minutes: 1) }
    }
  }
}
