import Foundation
import Synchronization
import TestSupport
import Testing

@testable import Proxy

/// Never answers. Records each request it was handed and each one URLSession took back.
final class HangingProtocol: URLProtocol {
  static let started = Mutex<Int>(0)
  static let stopped = Mutex<Int>(0)

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() { Self.started.withLock { $0 += 1 } }
  override func stopLoading() { Self.stopped.withLock { $0 += 1 } }
}

/// Every suite on `StubProtocol` shares its static reply and log, so they run one at a time.
@Suite(.serialized) enum StubbedTransportTests {}

extension StubbedTransportTests {
  @Suite struct SpeakTests {
    let client = ProxyClient(
      baseURL: URL(string: "https://ooooh.test")!, token: "attest",
      session: StubProtocol.session())

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
      StubProtocol.reset()
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

    @Test func cancellingTheReaderCancelsTheRequest() async throws {
      let client = ProxyClient(
        baseURL: URL(string: "https://ooooh.test")!, token: "attest",
        session: .stubbed(by: HangingProtocol.self))
      let reading = Task {
        var chunks = 0
        for try await _ in client.speak(text: "Does that settle it?") { chunks += 1 }
        return chunks
      }
      await wait { HangingProtocol.started.withLock { $0 } == 1 }
      #expect(HangingProtocol.stopped.withLock { $0 } == 0)
      reading.cancel()
      #expect(try await reading.value == 0)
      await wait { HangingProtocol.stopped.withLock { $0 } == 1 }
      #expect(HangingProtocol.stopped.withLock { $0 } == 1)
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
