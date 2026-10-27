import Foundation
import Synchronization

/// Answers every request through the real URLSession stack. One stub per test, set before the
/// call; `queue` answers in order first, then `reply` answers everything after.
public final class StubProtocol: URLProtocol {
  public struct Reply: Sendable {
    public var status: Int
    public var chunks: [Data]
    public var headers: [String: String]

    public init(status: Int, chunks: [Data], headers: [String: String] = [:]) {
      self.status = status
      self.chunks = chunks
      self.headers = headers
    }
  }

  nonisolated(unsafe) public static var reply = Reply(status: 200, chunks: [])
  public static let queue = Mutex<[Reply]>([])
  public static let seen = Mutex<[URLRequest]>([])

  public static func session() -> URLSession { .stubbed(by: StubProtocol.self) }

  /// Forgets the requests seen so far, so the next one is `seen.first`.
  public static func reset() { seen.withLock { $0 = [] } }

  override public class func canInit(with request: URLRequest) -> Bool { true }
  override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override public func startLoading() {
    Self.seen.withLock { $0.append(request) }
    let reply = Self.queue.withLock { $0.isEmpty ? Self.reply : $0.removeFirst() }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    for chunk in reply.chunks { client?.urlProtocol(self, didLoad: chunk) }
    client?.urlProtocolDidFinishLoading(self)
  }

  override public func stopLoading() {}
}

extension URLSession {
  /// An ephemeral session that hands every request to `protocolClass`.
  public static func stubbed(by protocolClass: URLProtocol.Type) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [protocolClass]
    return URLSession(configuration: configuration)
  }
}

extension URLRequest {
  /// URLSession hands protocols the body as a stream, so read it back.
  public var bodyBytes: Data {
    guard let stream = httpBodyStream else { return httpBody ?? Data() }
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
