import Foundation
import Governor
import State
import Testing

@testable import Proxy

extension StubbedTransportTests {
  /// `config.json` is what the Worker's `/v1/config` serves, written by its node project.
  @Suite struct ConfigTests {
    let client: ProxyClient = {
      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [StubProtocol.self]
      return ProxyClient(
        baseURL: URL(string: "https://ooooh.test")!, session: URLSession(configuration: config))
    }()

    @Test func fetchesAndDecodesEveryField() async throws {
      StubProtocol.reply = .init(status: 200, chunks: [try fixture("config", "json")])
      StubProtocol.seen.withLock { $0 = [] }

      let config = try await client.config()

      let request = try #require(StubProtocol.seen.withLock { $0.first })
      #expect(request.url?.path() == "/v1/config")
      #expect(request.httpMethod == "GET")
      #expect(config.version == 5)
      #expect(config.floor == .init(min: 30, max: 120))
      #expect(config.speak == .init(probability: 0.9, confidence: 0))
      #expect(config.finished == .init(probability: 0.6, confidence: 0.7))
      #expect(config.command == .init(probability: 0.9, confidence: 0.7))
      #expect(config.densityWindow == 120)
      #expect(config.endSilence == 30)
      #expect(config.silenceChecks == [5, 11, 20])
      #expect(config.armingDelay == 1.5)
      let weights: [String: Double] = [
        "hangingQuestion": 1.0, "trailsOff": 1.38, "unnamedDecision": 1.125,
      ]
      #expect(config.cueWeights == weights)
      let kinds: [String: InterventionKind] = [
        "hangingQuestion": .clarify, "trailsOff": .deepen, "unnamedDecision": .decide,
      ]
      #expect(config.cueKinds == kinds)
      #expect(config == .initial)
    }

    /// Re-encoding what was decoded has to give the served object back, so a field added on one
    /// side and not the other shows up as a missing or extra key.
    @Test func servesExactlyTheFieldsTheDecoderReads() throws {
      let served = try fixture("config", "json")
      let decoded = try JSONDecoder().decode(GovernorConfig.self, from: served)
      let reencoded = try JSONEncoder().encode(decoded)
      let servedObject = try JSONSerialization.jsonObject(with: served) as? NSDictionary
      let reencodedObject = try JSONSerialization.jsonObject(with: reencoded) as? NSDictionary
      #expect(servedObject == reencodedObject)
    }

    @Test func aWorkerErrorSurfacesWithItsStatus() async throws {
      StubProtocol.reply = .init(status: 503, chunks: [Data(#"{"error":"budget"}"#.utf8)])
      StubProtocol.seen.withLock { $0 = [] }
      await #expect(throws: ProxyError.status(503, body: #"{"error":"budget"}"#)) {
        try await client.config()
      }
    }
  }
}
