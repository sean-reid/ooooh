import Foundation
import Session
import State
import Transcription

/// `POST /v1/compact`: Haiku folds new transcript into a patch.
public struct HaikuCompactor: Compactor {
  public var client: ProxyClient

  public init(client: ProxyClient) {
    self.client = client
  }

  struct Body: Encodable {
    var state: CompactState
    var transcript: [WireSegment]
  }

  public struct Response: Decodable, Equatable, Sendable {
    public var patch: StatePatch
    public var usage: ProviderUsage
  }

  public func compact(state: CompactState, transcript: [Segment]) async throws -> StatePatch {
    let body = Body(state: state, transcript: transcript.map(WireSegment.init))
    let response: Response = try await client.post("v1/compact", body: body)
    return response.patch
  }
}
