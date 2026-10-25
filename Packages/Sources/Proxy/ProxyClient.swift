import CryptoKit
import Foundation
import Governor
import Session

#if os(iOS)
  import DeviceCheck
#endif

/// The Worker contract. One route per provider, all authenticated the same way.
public struct ProxyClient: Sendable {
  public var baseURL: URL
  public var session: URLSession
  /// Sent as `Authorization: Bearer` when set.
  public var token: String?
  /// Signs every body as `x-device` and `x-assertion` when set.
  public var attestor: (any Attestor)?
  /// Counts transport failures and successes when set.
  public var offline: OfflineGuard?

  public init(
    baseURL: URL, token: String? = nil, session: URLSession = .shared,
    attestor: (any Attestor)? = nil, offline: OfflineGuard? = nil
  ) {
    self.baseURL = baseURL
    self.token = token
    self.session = session
    self.attestor = attestor
    self.offline = offline
  }

  /// App Attest on a phone, nothing on the simulator or a Mac.
  public static func attestor(baseURL: URL, session: URLSession = .shared) -> any Attestor {
    #if os(iOS)
      if DCAppAttestService.shared.isSupported {
        return DeviceAttestation(baseURL: baseURL, session: session)
      }
    #endif
    return SimulatorAttestor()
  }

  /// Jev decides, Haiku compacts with a local fallback, Sonnet phrases.
  public func sessionDependencies() -> SessionLoop.Dependencies {
    SessionLoop.Dependencies(
      decisions: JevDecisionProvider(client: self),
      compactor: FallbackCompactor(
        primary: HaikuCompactor(client: self), fallback: PassthroughCompactor()),
      phraser: SonnetPhraser(client: self))
  }

  public func config() async throws -> GovernorConfig {
    let (data, response) = try await transport {
      try await session.data(from: baseURL.appending(path: "v1/config"))
    }
    try ProxyError.check(response, data: data)
    return try JSONDecoder().decode(GovernorConfig.self, from: data)
  }

  func request(_ path: String, body: some Encodable, accept: String = "application/json")
    async throws -> URLRequest
  {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = "POST"
    let bytes = try JSONEncoder().encode(body)
    request.httpBody = bytes
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(accept, forHTTPHeaderField: "Accept")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let attestor,
      let assertion = try await attestor.assertion(bodyHash: Data(SHA256.hash(data: bytes)))
    {
      request.setValue(assertion.keyId, forHTTPHeaderField: "x-device")
      request.setValue(assertion.assertion.base64EncodedString(), forHTTPHeaderField: "x-assertion")
    }
    return request
  }

  func post<Output: Decodable>(_ path: String, body: some Encodable, as: Output.Type = Output.self)
    async throws -> Output
  {
    let request = try await request(path, body: body)
    let (data, response) = try await transport { try await session.data(for: request) }
    try ProxyError.check(response, data: data)
    return try JSONDecoder().decode(Output.self, from: data)
  }

  /// Reports the outcome of one round trip to the guard. An HTTP error is still a reachable Worker.
  func transport<T>(_ send: () async throws -> T) async throws -> T {
    do {
      let value = try await send()
      offline?.recordSuccess()
      return value
    } catch {
      offline?.recordFailure(error)
      throw error
    }
  }
}

public enum ProxyError: Error, Equatable, Sendable {
  case status(Int, body: String)
  case notHTTP
  case stream(String)
  case attestation(String)

  static func check(_ response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else { throw ProxyError.notHTTP }
    guard (200..<300).contains(http.statusCode) else {
      throw ProxyError.status(http.statusCode, body: String(decoding: data, as: UTF8.self))
    }
  }
}
