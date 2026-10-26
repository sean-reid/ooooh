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
  /// Signs every request as `x-device`, `x-assertion-time`, and `x-assertion` when set.
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
    let url = baseURL.appending(path: path)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    let bytes = try JSONEncoder().encode(body)
    request.httpBody = bytes
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(accept, forHTTPHeaderField: "Accept")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let attestor {
      let clientData = ClientData(
        method: "POST", path: url.path(percentEncoded: true),
        time: Int(Date().timeIntervalSince1970), bodyHash: Data(SHA256.hash(data: bytes)))
      if let assertion = try await attestor.assertion(clientDataHash: clientData.hash) {
        request.setValue(assertion.keyId, forHTTPHeaderField: "x-device")
        request.setValue(String(clientData.time), forHTTPHeaderField: ClientData.timeHeader)
        request.setValue(
          assertion.assertion.base64EncodedString(), forHTTPHeaderField: "x-assertion")
      }
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
  /// 402 `no-session`: the device has no open session, or its free prompt minutes are spent.
  case noSession(reason: String)
  /// 401 `unauthorized` with the check that failed as `reason`.
  case unauthorized(reason: String)
  case notHTTP
  case stream(String)
  case attestation(String)

  static func check(_ response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else { throw ProxyError.notHTTP }
    guard (200..<300).contains(http.statusCode) else { throw failure(http.statusCode, data) }
  }

  static func failure(_ status: Int, _ body: Data) -> ProxyError {
    struct Refusal: Decodable {
      var error: String
      var reason: String
    }
    let refusal = try? JSONDecoder().decode(Refusal.self, from: body)
    switch (status, refusal?.error) {
    case (402, "no-session"): return .noSession(reason: refusal!.reason)
    case (401, "unauthorized"): return .unauthorized(reason: refusal!.reason)
    default: return .status(status, body: String(decoding: body, as: UTF8.self))
    }
  }
}
