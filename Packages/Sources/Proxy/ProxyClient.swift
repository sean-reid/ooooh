import Foundation
import Governor

/// The Worker contract. One route per provider, all authenticated the same way.
public struct ProxyClient: Sendable {
  public var baseURL: URL
  public var session: URLSession

  public init(baseURL: URL, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.session = session
  }

  public func config() async throws -> GovernorConfig {
    let (data, _) = try await session.data(from: baseURL.appending(path: "v1/config"))
    return try JSONDecoder().decode(GovernorConfig.self, from: data)
  }
}
