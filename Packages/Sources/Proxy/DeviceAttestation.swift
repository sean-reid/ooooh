import CryptoKit
import DeviceCheck
import Foundation

/// App Attest for one install: a key made once and attested through the Worker, then one
/// assertion per request. The key id lives in the keychain so a relaunch reuses it.
public actor DeviceAttestation: Attestor {
  let baseURL: URL
  let session: URLSession
  private let service: any AppAttestService
  private let store: any KeyIdStore
  private var keyId: String?
  private var enrolment: Task<String, Error>?
  /// Set once App Attest refuses this install for good; every later call fails the same way.
  private var cannotAttest: ProxyError?

  public init(baseURL: URL, session: URLSession = .shared) {
    self.init(
      baseURL: baseURL, session: session, service: DCAppAttestService.shared,
      store: KeychainKeyIdStore())
  }

  init(baseURL: URL, session: URLSession, service: any AppAttestService, store: any KeyIdStore) {
    self.baseURL = baseURL
    self.session = session
    self.service = service
    self.store = store
  }

  public func assertion(clientDataHash: Data) async throws -> Assertion? {
    let keyId = try await attestedKeyId()
    do {
      return Assertion(
        keyId: keyId,
        assertion: try await service.generateAssertion(keyId, clientDataHash: clientDataHash))
    } catch let error as DCError where error.code == .invalidKey {
      forget()
      let fresh = try await attestedKeyId()
      return Assertion(
        keyId: fresh,
        assertion: try await attest {
          try await service.generateAssertion(fresh, clientDataHash: clientDataHash)
        })
    } catch {
      throw mapped(error)
    }
  }

  public func keyId() async throws -> String? { try await attestedKeyId() }

  private func attestedKeyId() async throws -> String {
    if let cannotAttest { throw cannotAttest }
    if let keyId { return keyId }
    if let stored = try store.read() {
      keyId = stored
      return stored
    }
    if let enrolment { return try await enrolment.value }
    let task = Task { try await enrol() }
    enrolment = task
    defer { enrolment = nil }
    let id = try await task.value
    keyId = id
    return id
  }

  /// The challenge comes first, so a Worker that does not answer costs no App Attest key.
  private func enrol() async throws -> String {
    let (challengeData, challengeResponse) = try await session.data(
      from: baseURL.appending(path: "v1/challenge"))
    try ProxyError.check(challengeResponse, data: challengeData)
    let challenge = try JSONDecoder().decode(ChallengeResponse.self, from: challengeData)
      .challenge
    guard let challengeBytes = Data(base64Encoded: challenge) else {
      throw ProxyError.attestation("challenge is not base64")
    }
    let keyId = try await attest { try await service.generateKey() }
    let attestation = try await attest {
      try await service.attestKey(keyId, clientDataHash: Data(SHA256.hash(data: challengeBytes)))
    }

    var request = URLRequest(url: baseURL.appending(path: "v1/attest"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
      AttestBody(
        keyId: keyId, attestation: attestation.base64EncodedString(), challenge: challenge))
    let (data, response) = try await session.data(for: request)
    try ProxyError.check(response, data: data)
    try store.write(keyId)
    return keyId
  }

  private func attest<T>(_ call: () async throws -> T) async throws -> T {
    do {
      return try await call()
    } catch {
      throw mapped(error)
    }
  }

  private func mapped(_ error: any Error) -> any Error {
    guard let dcError = error as? DCError else { return error }
    let proxyError = ProxyError(dcError)
    if case .cannotAttest = proxyError { cannotAttest = proxyError }
    return proxyError
  }

  private func forget() {
    keyId = nil
    store.delete()
  }
}
