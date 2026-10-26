import Foundation
import Governor
import Session
import State

/// `POST /v1/decide`: Jev's answers for one check.
public struct JevDecisionProvider: DecisionProvider {
  public var client: ProxyClient

  public init(client: ProxyClient) {
    self.client = client
  }

  struct Body: Encodable {
    var state: CompactState
    var recentTranscript: [WireSegment]
    var signals: WireSignals
    var lastIntervention: CompactState.Intervention?
  }

  public struct Response: Decodable, Equatable, Sendable {
    public var answers: JevAnswers
    public var questionsVersion: Int
    public var usage: ProviderUsage
  }

  /// Quiet rather than throwing while the Worker is offline, so the loop keeps running.
  public func check(_ input: CheckInput) async throws -> JevAnswers {
    if let offline = client.offline, !offline.allowsRequest() { return .quiet }
    do {
      return try await decide(input).answers
    } catch  where client.offline?.isOffline == true {
      return .quiet
    }
  }

  public func decide(_ input: CheckInput) async throws -> Response {
    let body = Body(
      state: input.state,
      recentTranscript: input.recentTranscript.map(WireSegment.init),
      signals: WireSignals(input.signals),
      lastIntervention: input.state.lastIntervention)
    return try await client.post("v1/decide", body: body)
  }
}
