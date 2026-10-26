import Foundation
import Synchronization

/// Answers the Worker routes by host and path, so the tests run side by side; an unanswered
/// path is a 404 and the end a 204. Reads each body back, since URLSession hands it over as
/// a stream.
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

  static func session() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GateProtocol.self]
    return URLSession(configuration: configuration)
  }

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
          host: host, path: path, headers: request.allHTTPHeaderFields ?? [:], body: readBody()))
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

  private func readBody() -> Data {
    guard let stream = request.httpBodyStream else { return request.httpBody ?? Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }
}

/// Refuses every request at once, so going offline does not depend on the host's network stack.
final class UnreachableProtocol: URLProtocol {
  /// Every path refused, with the seconds since the first, for the failure message.
  static let seen = Mutex<[String]>([])
  static let started = Mutex<Date?>(nil)

  static func session() -> URLSession {
    seen.withLock { $0 = [] }
    started.withLock { $0 = nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UnreachableProtocol.self]
    return URLSession(configuration: configuration)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let now = Date()
    let first = Self.started.withLock { started -> Date in
      if let started { return started }
      started = now
      return now
    }
    let path = request.url?.path ?? "?"
    Self.seen.withLock {
      $0.append("\(path)@\(String(format: "%.2f", now.timeIntervalSince(first)))s")
    }
    client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
  }
  override func stopLoading() {}
}

@MainActor func wait(_ condition: @MainActor () -> Bool, seconds: Double = 10) async {
  let deadline = ContinuousClock.now + .seconds(seconds)
  while !condition(), ContinuousClock.now < deadline {
    try? await Task.sleep(for: .milliseconds(10))
  }
}
