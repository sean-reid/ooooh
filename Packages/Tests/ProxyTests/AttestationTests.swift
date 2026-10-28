import CryptoKit
import Foundation
import Synchronization
import TestSupport
import Testing

@testable import Proxy

/// Records the hash it was asked to sign and answers with a fixed assertion, nothing, or a failure.
final class FakeAttestor: Attestor {
  let hashes = Mutex<[Data]>([])
  let reply: Assertion?
  let failure: (any Error)?

  init(reply: Assertion?, failure: (any Error)? = nil) {
    self.reply = reply
    self.failure = failure
  }

  func assertion(clientDataHash: Data) async throws -> Assertion? {
    hashes.withLock { $0.append(clientDataHash) }
    if let failure { throw failure }
    return reply
  }

  func keyId() async throws -> String? {
    if let failure { throw failure }
    return reply?.keyId
  }
}

extension StubbedTransportTests {
  @Suite struct AttestationTests {
    func client(
      _ attestor: any Attestor, offline: OfflineGuard? = nil, clock: WorkerClock = WorkerClock()
    ) -> ProxyClient {
      ProxyClient(
        baseURL: URL(string: "https://ooooh.test")!, session: StubProtocol.session(),
        attestor: attestor, offline: offline, clock: clock)
    }

    let signing = FakeAttestor(reply: Assertion(keyId: "key-1", assertion: Data([0xa2, 0x01])))
    let stale = StubProtocol.Reply(
      status: 401, chunks: [Data(#"{"error":"unauthorized","reason":"stale"}"#.utf8)])
    let phrased = StubProtocol.Reply(status: 200, chunks: [Data(#"{"text":"Which part?"}"#.utf8)])

    /// What a Worker whose clock runs `ahead` seconds of this machine's puts in its Date header.
    func serverDate(ahead: TimeInterval, from device: Date = .now) -> (header: String, seconds: Int)
    {
      let seconds = Int(device.timeIntervalSince1970.rounded(.down)) + Int(ahead)
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
      return (formatter.string(from: Date(timeIntervalSince1970: Double(seconds))), seconds)
    }

    func signedTimes() throws -> [Int] {
      try StubProtocol.seen.withLock { $0 }.map {
        try #require($0.value(forHTTPHeaderField: ClientData.timeHeader).flatMap { Int($0) })
      }
    }

    @Test func aStaleAnswerTeachesTheWorkersClockAndTheRetrySignsWithIt() async throws {
      let device = Date(timeIntervalSince1970: 1_793_000_000)
      let clock = WorkerClock(now: { device })
      let server = serverDate(ahead: 1_000, from: device)
      var stale = stale
      stale.headers = ["Date": server.header]
      StubProtocol.queue.withLock { $0 = [stale, phrased] }
      StubProtocol.reset()

      let response: SonnetPhraser.Response = try await client(signing, clock: clock).post(
        "v1/phrase", body: ["kind": "clarify"])
      #expect(response.text == "Which part?")

      let times = try signedTimes()
      #expect(times.count == 2)
      #expect(times[0] == server.seconds - 1_000)
      #expect(times[1] == server.seconds)
      #expect(clock.offset == 1_000)
      #expect(!clock.isRefused)
      #expect(StubProtocol.queue.withLock { $0.isEmpty })
    }

    @Test func twoStaleAnswersAreAClockSkewWithNoThirdRequest() async throws {
      let clock = WorkerClock()
      let changes = clock.changes()
      StubProtocol.queue.withLock { $0 = [stale, stale] }
      StubProtocol.reply = phrased
      StubProtocol.reset()

      await #expect(throws: ProxyError.clockSkew) {
        let _: SonnetPhraser.Response = try await client(signing, clock: clock).post(
          "v1/phrase", body: ["kind": "clarify"])
      }

      #expect(StubProtocol.seen.withLock { $0.count } == 2)
      #expect(clock.isRefused)
      for await refused in changes {
        #expect(refused)
        break
      }
    }

    @Test func aStaleAnswerLeavesTheOfflineGuardOnline() async throws {
      let guardian = OfflineGuard()
      StubProtocol.queue.withLock { $0 = [stale, stale] }
      StubProtocol.reset()

      await #expect(throws: ProxyError.clockSkew) {
        let _: SonnetPhraser.Response = try await client(signing, offline: guardian).post(
          "v1/phrase", body: ["kind": "clarify"])
      }

      #expect(!guardian.isOffline)
      guardian.recordFailure(URLError(.cannotConnectToHost))
      #expect(!guardian.isOffline)
    }

    @Test func signsTheMethodPathTimeAndBodyAndSendsAllThreeHeaders() async throws {
      let attestor = FakeAttestor(
        reply: Assertion(keyId: "key-1", assertion: Data([0xa2, 0x01, 0x02])))
      StubProtocol.reply = .init(status: 200, chunks: [Data(#"{"text":"Which part?"}"#.utf8)])
      StubProtocol.reset()

      let before = Int(Date().timeIntervalSince1970)
      let response: SonnetPhraser.Response = try await client(attestor).post(
        "v1/phrase", body: ["kind": "clarify"])
      #expect(response.text == "Which part?")

      let request = try #require(StubProtocol.seen.withLock { $0.first })
      #expect(request.value(forHTTPHeaderField: "x-device") == "key-1")
      #expect(request.value(forHTTPHeaderField: "x-assertion") == "ogEC")
      #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
      let header = try #require(request.value(forHTTPHeaderField: "x-assertion-time"))
      let time = try #require(Int(header))
      #expect((before...before + 5).contains(time))
      let signed = ClientData(
        method: "POST", path: "/v1/phrase", time: time,
        bodyHash: Data(SHA256.hash(data: request.bodyBytes)))
      #expect(attestor.hashes.withLock { $0 } == [signed.hash])
    }

    @Test func sendsNoAttestationHeadersWhenTheAttestorHasNone() async throws {
      let attestor = FakeAttestor(reply: nil)
      StubProtocol.reply = .init(status: 200, chunks: [Data(#"{"text":"Which part?"}"#.utf8)])
      StubProtocol.reset()

      let _: SonnetPhraser.Response = try await client(attestor).post(
        "v1/phrase", body: ["kind": "clarify"])

      let request = try #require(StubProtocol.seen.withLock { $0.first })
      #expect(request.value(forHTTPHeaderField: "x-device") == nil)
      #expect(request.value(forHTTPHeaderField: "x-assertion") == nil)
      #expect(request.value(forHTTPHeaderField: "x-assertion-time") == nil)
      #expect(attestor.hashes.withLock { $0.count } == 1)
    }

    @Test func anAttestorFailureCountsAgainstTheOfflineGuard() async throws {
      let guardian = OfflineGuard(failuresToTrip: 1)
      let attestor = FakeAttestor(reply: nil, failure: ProxyError.attestation("server-unavailable"))
      StubProtocol.reset()
      var client = client(attestor)
      client.offline = guardian

      await #expect(throws: ProxyError.attestation("server-unavailable")) {
        let _: SonnetPhraser.Response = try await client.post(
          "v1/phrase", body: ["kind": "clarify"])
      }
      #expect(guardian.isOffline)
      #expect(StubProtocol.seen.withLock { $0.isEmpty })
    }

    @Test func simulatorAttestorSignsNothingAndHasNoKeyId() async throws {
      #expect(try await SimulatorAttestor().assertion(clientDataHash: Data(count: 32)) == nil)
      #expect(try await SimulatorAttestor().keyId() == nil)
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
