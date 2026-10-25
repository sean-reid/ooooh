#if os(iOS)
  import CryptoKit
  import DeviceCheck
  import Foundation
  import Security

  /// App Attest for one install: a key made once and attested through the Worker, then one
  /// assertion per request. The key id lives in the keychain so a relaunch reuses it.
  public actor DeviceAttestation: Attestor {
    let baseURL: URL
    let session: URLSession
    private let service = DCAppAttestService.shared
    private var keyId: String?
    private var enrolment: Task<String, Error>?

    public init(baseURL: URL, session: URLSession = .shared) {
      self.baseURL = baseURL
      self.session = session
      keyId = KeyIdStore.read()
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
          assertion: try await service.generateAssertion(fresh, clientDataHash: clientDataHash))
      }
    }

    private func attestedKeyId() async throws -> String {
      if let keyId { return keyId }
      if let enrolment { return try await enrolment.value }
      let task = Task { try await enrol() }
      enrolment = task
      defer { enrolment = nil }
      let id = try await task.value
      keyId = id
      return id
    }

    private func enrol() async throws -> String {
      let keyId = try await service.generateKey()
      let (challengeData, challengeResponse) = try await session.data(
        from: baseURL.appending(path: "v1/challenge"))
      try ProxyError.check(challengeResponse, data: challengeData)
      let challenge = try JSONDecoder().decode(ChallengeResponse.self, from: challengeData)
        .challenge
      guard let challengeBytes = Data(base64Encoded: challenge) else {
        throw ProxyError.attestation("challenge is not base64")
      }
      let attestation = try await service.attestKey(
        keyId, clientDataHash: Data(SHA256.hash(data: challengeBytes)))

      var request = URLRequest(url: baseURL.appending(path: "v1/attest"))
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(
        AttestBody(
          keyId: keyId, attestation: attestation.base64EncodedString(), challenge: challenge))
      let (data, response) = try await session.data(for: request)
      try ProxyError.check(response, data: data)
      KeyIdStore.write(keyId)
      return keyId
    }

    private func forget() {
      keyId = nil
      KeyIdStore.delete()
    }
  }

  /// The attested key id, one keychain item for the app.
  enum KeyIdStore {
    static var query: [CFString: Any] {
      [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "com.seanreid.ooooh.appattest",
        kSecAttrAccount: "keyId",
      ]
    }

    static func read() -> String? {
      var item: CFTypeRef?
      let status = SecItemCopyMatching(
        query.merging([kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]) { $1 }
          as CFDictionary, &item)
      guard status == errSecSuccess, let data = item as? Data else { return nil }
      return String(data: data, encoding: .utf8)
    }

    static func write(_ keyId: String) {
      delete()
      SecItemAdd(
        query.merging([
          kSecValueData: Data(keyId.utf8),
          kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) { $1 } as CFDictionary, nil)
    }

    static func delete() {
      SecItemDelete(query as CFDictionary)
    }
  }
#endif
