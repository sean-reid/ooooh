import Foundation
import Synchronization
import Testing

@testable import Proxy

/// Answers every request through the real URLSession stack. One stub per test, set before the call.
final class StubProtocol: URLProtocol {
  struct Reply: Sendable {
    var status: Int
    var chunks: [Data]
  }
  nonisolated(unsafe) static var reply = Reply(status: 200, chunks: [])
  static let seen = Mutex<[URLRequest]>([])

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.seen.withLock { $0.append(request) }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: Self.reply.status, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    for chunk in Self.reply.chunks { client?.urlProtocol(self, didLoad: chunk) }
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

extension URLRequest {
  /// URLSession hands protocols the body as a stream, so read it back.
  var bodyBytes: Data {
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

/// Every suite on `StubProtocol` shares its static reply and log, so they run one at a time.
@Suite(.serialized) enum StubbedTransportTests {}

extension StubbedTransportTests {
  @Suite struct SpeakTests {
    let client: ProxyClient = {
      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [StubProtocol.self]
      return ProxyClient(
        baseURL: URL(string: "https://ooooh.test")!, token: "attest",
        session: URLSession(configuration: config))
    }()

    let audio = Data((0..<2500).map { UInt8($0 % 251) })

    @Test func chunksABytesSequenceIntoFixedPiecesWithARemainder() async throws {
      let bytes = AsyncStream<UInt8> { continuation in
        for byte in audio { continuation.yield(byte) }
        continuation.finish()
      }
      var chunks: [Data] = []
      for try await chunk in Chunked(bytes, size: 1024) { chunks.append(chunk) }
      #expect(chunks.map(\.count) == [1024, 1024, 452])
      #expect(chunks.reduce(Data(), +) == audio)
    }

    @Test func postsTheLineAndStreamsTheAudioBack() async throws {
      StubProtocol.reply = .init(status: 200, chunks: [audio.prefix(700), audio.dropFirst(700)])
      StubProtocol.seen.withLock { $0 = [] }
      var received = Data()
      var chunks = 0
      for try await chunk in client.speak(text: "Does that settle it?") {
        received.append(chunk)
        chunks += 1
      }
      #expect(received == audio)
      #expect(chunks == 3)

      let request = try #require(StubProtocol.seen.withLock { $0.first })
      #expect(request.url?.path() == "/v1/speak")
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "Accept") == "audio/mpeg")
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer attest")
      let body = try JSONDecoder().decode([String: String].self, from: request.bodyBytes)
      #expect(body == ["text": "Does that settle it?"])
    }

    @Test func surfacesAWorkerErrorWithItsBody() async throws {
      StubProtocol.reply = .init(
        status: 503, chunks: [Data(#"{"error":"elevenlabs unavailable"}"#.utf8)])
      await #expect(throws: ProxyError.status(503, body: #"{"error":"elevenlabs unavailable"}"#)) {
        for try await _ in client.speak(text: "Does that settle it?") {}
      }
    }
  }
}
