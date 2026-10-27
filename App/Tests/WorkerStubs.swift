import Foundation
import Synchronization
import TestSupport

/// Answers the Worker routes by host and path, so the tests run side by side; an unanswered
/// path is a 404 and the end a 204.
final class GateProtocol: URLProtocol {
  struct Request: Sendable {
    var host: String
    var path: String
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? {
      headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
  }

  static let answers = Mutex<[String: [String: (status: Int, body: Data)]]>([:])
  static let seen = Mutex<[Request]>([])

  static func answer(_ host: String, _ path: String, _ status: Int, _ body: Data) {
    answers.withLock { $0[host, default: [:]][path] = (status, body) }
  }

  static func session() -> URLSession { .stubbed(by: GateProtocol.self) }

  static func requests(to host: String) -> [Request] {
    seen.withLock { $0.filter { $0.host == host } }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let host = request.url?.host() ?? ""
    let path = request.url?.path() ?? ""
    Self.seen.withLock {
      $0.append(
        Request(
          host: host, path: path, headers: request.allHTTPHeaderFields ?? [:],
          body: request.bodyBytes))
    }
    let (status, body): (Int, Data) =
      Self.answers.withLock { $0[host]?[path] }
      ?? (path == "/v1/session/end" ? (204, Data()) : (404, Data()))
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
