import Foundation
import Governor
import Session

/// The Worker contract. One route per provider, all authenticated the same way.
public struct ProxyClient: Sendable {
  public var baseURL: URL
  public var session: URLSession
  /// Sent as `Authorization: Bearer`. Will carry the App Attest token.
  public var token: String?
  /// Counts transport failures and successes when set.
  public var offline: OfflineGuard?

  public init(
    baseURL: URL, token: String? = nil, session: URLSession = .shared,
    offline: OfflineGuard? = nil
  ) {
    self.baseURL = baseURL
    self.token = token
    self.session = session
    self.offline = offline
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

  func request(_ path: String, body: some Encodable, accept: String = "application/json") throws
    -> URLRequest
  {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = "POST"
    request.httpBody = try JSONEncoder().encode(body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(accept, forHTTPHeaderField: "Accept")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    return request
  }

  func post<Output: Decodable>(_ path: String, body: some Encodable, as: Output.Type = Output.self)
    async throws -> Output
  {
    let request = try request(path, body: body)
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

  static func check(_ response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else { throw ProxyError.notHTTP }
    guard (200..<300).contains(http.statusCode) else {
      throw ProxyError.status(http.statusCode, body: String(decoding: data, as: UTF8.self))
    }
  }
}
