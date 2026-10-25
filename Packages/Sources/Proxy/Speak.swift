import Foundation

/// `POST /v1/speak`: the Worker streams MP3 from ElevenLabs and this hands the bytes on in small chunks.
extension ProxyClient {
  struct SpeakBody: Encodable {
    var text: String
  }

  /// 1 KiB is 128 ms of audio at 64 kbps, small enough that the player starts on the first chunk.
  static let speechChunkBytes = 1024

  public func speak(text: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let request = try request("v1/speak", body: SpeakBody(text: text), accept: "audio/mpeg")
          let (bytes, response) = try await session.bytes(for: request)
          try await ProxyError.check(response, bytes: bytes)
          for try await chunk in Chunked(bytes, size: Self.speechChunkBytes) {
            continuation.yield(chunk)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

extension ProxyError {
  static func check(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
    guard let http = response as? HTTPURLResponse else { throw ProxyError.notHTTP }
    guard (200..<300).contains(http.statusCode) else {
      var body = Data()
      for try await byte in bytes { body.append(byte) }
      throw ProxyError.status(http.statusCode, body: String(decoding: body, as: UTF8.self))
    }
  }
}

/// Groups a byte sequence into `Data` of `size` bytes; the last one is whatever remains.
struct Chunked<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
  typealias Element = Data

  var base: Base
  var size: Int

  init(_ base: Base, size: Int) {
    self.base = base
    self.size = size
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    var base: Base.AsyncIterator
    var size: Int
    var drained = false

    mutating func next() async throws -> Data? {
      if drained { return nil }
      var chunk = Data(capacity: size)
      while chunk.count < size, let byte = try await base.next() {
        chunk.append(byte)
      }
      if chunk.count < size { drained = true }
      return chunk.isEmpty ? nil : chunk
    }
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(base: base.makeAsyncIterator(), size: size)
  }
}
