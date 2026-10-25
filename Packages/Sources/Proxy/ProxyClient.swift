import Foundation
import Governor

/// The Worker contract. One route per provider, all authenticated the same way.
public struct ProxyClient: Sendable {
  public var baseURL: URL
  public var session: URLSession
  /// Sent as `Authorization: Bearer`. Will carry the App Attest token.
  public var token: String?

  public init(baseURL: URL, token: String? = nil, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.token = token
    self.session = session
  }

  public func config() async throws -> GovernorConfig {
    let (data, _) = try await session.data(from: baseURL.appending(path: "v1/config"))
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
    let (data, response) = try await session.data(for: try request(path, body: body))
    try ProxyError.check(response, data: data)
    return try JSONDecoder().decode(Output.self, from: data)
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
