import Foundation
import Session
import State
import Transcription

/// `POST /v1/phrase`: Sonnet writes the one sentence, whole or streamed.
public struct SonnetPhraser: Phraser {
  public var client: ProxyClient

  public init(client: ProxyClient) {
    self.client = client
  }

  struct Body: Encodable {
    var kind: InterventionKind
    var state: CompactState
    var recent: [WireSegment]
    var lastIntervention: CompactState.Intervention?
    var said: [CompactState.Intervention]
  }

  public struct Response: Decodable, Equatable, Sendable {
    public var text: String
  }

  /// What the streaming route sends. `done` carries the final text, which can differ from the
  /// joined deltas when the Worker had to ask for a shorter sentence.
  public enum Event: Equatable, Sendable {
    case delta(String)
    case done(String)
  }

  public func phrase(
    _ kind: InterventionKind, state: CompactState, recent: [Segment],
    said: [CompactState.Intervention]
  ) async throws -> String {
    let response: Response = try await client.post(
      "v1/phrase", body: body(kind, state, recent, said))
    return response.text
  }

  public func stream(
    _ kind: InterventionKind, state: CompactState, recent: [Segment],
    said: [CompactState.Intervention]
  ) -> AsyncThrowingStream<Event, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let request = try await client.request(
            "v1/phrase", body: body(kind, state, recent, said), accept: "text/event-stream")
          let (bytes, response) = try await client.session.bytes(for: request)
          try ProxyError.check(response, data: Data())
          for try await event in ServerSentEvents.events(from: bytes.lines) {
            if let parsed = try Self.event(from: event) { continuation.yield(parsed) }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  static func event(from event: ServerSentEvent) throws -> Event? {
    struct Payload: Decodable {
      var text: String?
      var error: String?
    }
    let payload = try JSONDecoder().decode(Payload.self, from: Data(event.data.utf8))
    switch event.event {
    case "delta": return .delta(payload.text ?? "")
    case "done": return .done(payload.text ?? "")
    case "error": throw ProxyError.stream(payload.error ?? event.data)
    default: return nil
    }
  }

  private func body(
    _ kind: InterventionKind, _ state: CompactState, _ recent: [Segment],
    _ said: [CompactState.Intervention]
  ) -> Body {
    Body(
      kind: kind, state: state, recent: recent.map(WireSegment.init),
      lastIntervention: state.lastIntervention, said: said)
  }
}
