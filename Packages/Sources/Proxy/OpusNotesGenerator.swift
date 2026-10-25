import Foundation
import Notes
import State
import Transcription

/// `POST /v1/notes`: Opus writes the session notes once the session ends.
public struct OpusNotesGenerator: NotesGenerator {
  public var client: ProxyClient

  public init(client: ProxyClient) {
    self.client = client
  }

  struct Body: Encodable {
    var state: CompactState
    var transcript: [WireSegment]
  }

  public struct Response: Decodable, Equatable, Sendable {
    public var notes: SessionNotes
    public var usage: ProviderUsage
  }

  public func generate(state: CompactState, transcript: [Segment]) async throws -> SessionNotes {
    let body = Body(state: state, transcript: transcript.map(WireSegment.init))
    let response: Response = try await client.post("v1/notes", body: body)
    return response.notes
  }
}
