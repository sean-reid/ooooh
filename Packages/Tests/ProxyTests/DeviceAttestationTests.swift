import CryptoKit
import DeviceCheck
import Foundation
import Synchronization
import TestSupport
import Testing

@testable import Proxy

/// Records each App Attest call in order and throws the next scripted error for that call.
final class FakeAppAttestService: AppAttestService {
  let calls = Mutex<[String]>([])
  private let keyIds: Mutex<[String]>
  private let failures: Mutex<[String: [any Error]]>

  init(keyIds: [String] = ["key-1", "key-2"], failing: [String: [any Error]] = [:]) {
    self.keyIds = Mutex(keyIds)
    self.failures = Mutex(failing)
  }

  func generateKey() async throws -> String {
    try record("generateKey")
    return keyIds.withLock { $0.removeFirst() }
  }

  func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
    try record("attestKey(\(keyId), \(ClientData.hex(clientDataHash)))")
    return Data([0xa1])
  }

  func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
    try record("generateAssertion(\(keyId))")
    return Data([0xa2])
  }

  private func record(_ call: String) throws {
    calls.withLock { $0.append(call) }
    let name = String(call.prefix { $0 != "(" })
    let next = failures.withLock { $0[name]?.isEmpty == false ? $0[name]!.removeFirst() : nil }
    if let next { throw next }
  }
}

final class MemoryKeyIdStore: KeyIdStore {
  let stored: Mutex<String?>
  let readFailure: (any Error)?
  let writeFailure: (any Error)?

  init(_ keyId: String? = nil, readFailure: (any Error)? = nil, writeFailure: (any Error)? = nil) {
    stored = Mutex(keyId)
    self.readFailure = readFailure
    self.writeFailure = writeFailure
  }

  func read() throws -> String? {
    if let readFailure { throw readFailure }
    return stored.withLock { $0 }
  }

  func write(_ keyId: String) throws {
    if let writeFailure { throw writeFailure }
    stored.withLock { $0 = keyId }
  }

  func delete() { stored.withLock { $0 = nil } }
}

extension StubbedTransportTests {
  @Suite struct DeviceAttestationTests {
    let hash = Data(count: 32)
    let challenge = Data("b".utf8)
    let keychainFailure = ProxyError.attestation("keychain write -34018")

    func attestor(_ service: FakeAppAttestService, _ store: MemoryKeyIdStore) -> DeviceAttestation {
      DeviceAttestation(
        baseURL: URL(string: "https://ooooh.test")!, session: StubProtocol.session(),
        service: service, store: store)
    }

    func workerAnswers(_ status: Int = 200) {
      StubProtocol.reply = .init(
        status: status, chunks: [Data(#"{"challenge":"\#(challenge.base64EncodedString())"}"#.utf8)]
      )
      StubProtocol.reset()
    }

    var requested: [String] { StubProtocol.seen.withLock { $0.compactMap { $0.url?.path() } } }

    @Test func enrolsAgainstTheChallengeThenStoresTheKeyId() async throws {
      let service = FakeAppAttestService()
      let store = MemoryKeyIdStore()
      workerAnswers()

      let assertion = try await attestor(service, store).assertion(clientDataHash: hash)

      #expect(assertion == Assertion(keyId: "key-1", assertion: Data([0xa2])))
      #expect(store.stored.withLock { $0 } == "key-1")
      #expect(requested == ["/v1/challenge", "/v1/attest"])
      let expectedHash = ClientData.hex(Data(SHA256.hash(data: challenge)))
      #expect(
        service.calls.withLock { $0 } == [
          "generateKey", "attestKey(key-1, \(expectedHash))", "generateAssertion(key-1)",
        ])
      let posted = try #require(StubProtocol.seen.withLock { $0.last })
      let body = try JSONSerialization.jsonObject(with: posted.bodyBytes) as? [String: String]
      #expect(body == ["keyId": "key-1", "attestation": "oQ==", "challenge": "Yg=="])
    }

    @Test func aChallengeTheWorkerRefusesCostsNoKey() async throws {
      let service = FakeAppAttestService()
      let store = MemoryKeyIdStore()
      workerAnswers(503)

      await #expect(throws: ProxyError.status(503, body: #"{"challenge":"Yg=="}"#)) {
        try await attestor(service, store).assertion(clientDataHash: hash)
      }
      #expect(service.calls.withLock { $0 } == [])
      #expect(store.stored.withLock { $0 } == nil)
    }

    @Test func aFailedKeychainWriteFailsEnrolmentAndKeepsNoKeyId() async throws {
      let service = FakeAppAttestService()
      let store = MemoryKeyIdStore(writeFailure: keychainFailure)
      workerAnswers()
      let attestor = attestor(service, store)

      await #expect(throws: keychainFailure) { try await attestor.assertion(clientDataHash: hash) }
      await #expect(throws: keychainFailure) { try await attestor.keyId() }

      #expect(store.stored.withLock { $0 } == nil)
      #expect(service.calls.withLock { $0.filter { $0 == "generateKey" }.count } == 2)
      #expect(requested == ["/v1/challenge", "/v1/attest", "/v1/challenge", "/v1/attest"])
    }

    @Test func aStoredKeyIdSignsWithoutEnrolling() async throws {
      let service = FakeAppAttestService()
      let store = MemoryKeyIdStore("key-9")
      workerAnswers()

      let assertion = try await attestor(service, store).assertion(clientDataHash: hash)

      #expect(assertion?.keyId == "key-9")
      #expect(requested == [])
      #expect(service.calls.withLock { $0 } == ["generateAssertion(key-9)"])
    }

    @Test func aKeychainThatCannotAnswerFailsTheRequestWithoutEnrolling() async throws {
      let failure = ProxyError.attestation("keychain read -25308")
      let service = FakeAppAttestService()
      workerAnswers()

      await #expect(throws: failure) {
        try await attestor(service, MemoryKeyIdStore(readFailure: failure))
          .assertion(clientDataHash: hash)
      }
      #expect(requested == [])
      #expect(service.calls.withLock { $0 } == [])
    }

    @Test func anInvalidKeyOnSigningEnrolsAFreshKeyOnce() async throws {
      let service = FakeAppAttestService(
        failing: ["generateAssertion": [DCError(.invalidKey)]])
      let store = MemoryKeyIdStore("key-old")
      workerAnswers()

      let assertion = try await attestor(service, store).assertion(clientDataHash: hash)

      #expect(assertion?.keyId == "key-1")
      #expect(store.stored.withLock { $0 } == "key-1")
      #expect(
        service.calls.withLock { $0.map { String($0.prefix { $0 != "," }) } } == [
          "generateAssertion(key-old)", "generateKey", "attestKey(key-1",
          "generateAssertion(key-1)",
        ])
    }

    @Test func aStoredKeyFromAnotherEnvironmentIsReplacedOnce() async throws {
      let service = FakeAppAttestService(
        failing: ["generateAssertion": [DCError(.invalidInput)]])
      let store = MemoryKeyIdStore("key-development")
      workerAnswers()

      let assertion = try await attestor(service, store).assertion(clientDataHash: hash)

      #expect(assertion?.keyId == "key-1")
      #expect(store.stored.withLock { $0 } == "key-1")
      #expect(requested == ["/v1/challenge", "/v1/attest"])
      #expect(
        service.calls.withLock { $0.map { String($0.prefix { $0 != "," }) } } == [
          "generateAssertion(key-development)", "generateKey", "attestKey(key-1",
          "generateAssertion(key-1)",
        ])
    }

    @Test func aFreshKeyRefusedTheSameWayStopsAttestingUntilRelaunch() async throws {
      let service = FakeAppAttestService(
        failing: ["generateAssertion": [DCError(.invalidInput), DCError(.invalidInput)]])
      let store = MemoryKeyIdStore("key-development")
      workerAnswers()
      let attestor = attestor(service, store)

      await #expect(throws: ProxyError.cannotAttest("invalid-input")) {
        try await attestor.assertion(clientDataHash: hash)
      }
      let calls = service.calls.withLock { $0.count }
      await #expect(throws: ProxyError.cannotAttest("invalid-input")) {
        try await attestor.assertion(clientDataHash: hash)
      }
      #expect(service.calls.withLock { $0.count } == calls)
    }

    @Test(arguments: [
      (DCError.serverUnavailable, ProxyError.attestation("server-unavailable")),
      (DCError.unknownSystemFailure, ProxyError.attestation("system-failure")),
      (DCError.invalidKey, ProxyError.attestation("invalid-key")),
      (DCError.featureUnsupported, ProxyError.cannotAttest("feature-unsupported")),
      (DCError.invalidInput, ProxyError.cannotAttest("invalid-input")),
    ])
    func mapsEachDCErrorCode(_ code: DCError.Code, _ expected: ProxyError) {
      #expect(ProxyError(DCError(code)) == expected)
    }

    @Test func aServerUnavailableFailureTriesAgainOnTheNextRequest() async throws {
      let service = FakeAppAttestService(failing: ["generateKey": [DCError(.serverUnavailable)]])
      let store = MemoryKeyIdStore()
      workerAnswers()
      let attestor = attestor(service, store)

      await #expect(throws: ProxyError.attestation("server-unavailable")) {
        try await attestor.assertion(clientDataHash: hash)
      }
      #expect(store.stored.withLock { $0 } == nil)

      let assertion = try await attestor.assertion(clientDataHash: hash)
      #expect(assertion?.keyId == "key-1")
      #expect(store.stored.withLock { $0 } == "key-1")
    }

    @Test func anUnsupportedInstallStopsAttestingUntilRelaunch() async throws {
      let service = FakeAppAttestService(
        failing: ["generateKey": [DCError(.featureUnsupported)]])
      let store = MemoryKeyIdStore()
      workerAnswers()
      let attestor = attestor(service, store)

      for _ in 0..<2 {
        await #expect(throws: ProxyError.cannotAttest("feature-unsupported")) {
          try await attestor.assertion(clientDataHash: hash)
        }
      }
      await #expect(throws: ProxyError.cannotAttest("feature-unsupported")) {
        try await attestor.keyId()
      }
      #expect(service.calls.withLock { $0 } == ["generateKey"])
      #expect(requested == ["/v1/challenge"])
      #expect(store.stored.withLock { $0 } == nil)
    }
  }
}
