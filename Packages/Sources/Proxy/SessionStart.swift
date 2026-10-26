import Foundation

/// What `POST /v1/session/start` answers: a free session with its limits, a paid one, or a refusal.
public enum SessionStart: Equatable, Sendable {
  case free(remaining: Int, promptMinutes: Int)
  case paid
  case refused(reason: String)
}

extension SessionStart: Decodable {
  enum CodingKeys: String, CodingKey {
    case allowed, free, remainingFree, promptMinutes, reason
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard try container.decode(Bool.self, forKey: .allowed) else {
      self = .refused(reason: try container.decode(String.self, forKey: .reason))
      return
    }
    guard try container.decode(Bool.self, forKey: .free) else {
      self = .paid
      return
    }
    self = .free(
      remaining: try container.decode(Int.self, forKey: .remainingFree),
      promptMinutes: try container.decode(Int.self, forKey: .promptMinutes))
  }
}

extension ProxyClient {
  struct StartBody: Encodable {}

  struct EndBody: Encodable {
    var minutes: Double
  }

  public func startSession() async throws -> SessionStart {
    try await post("v1/session/start", body: StartBody())
  }

  /// The Worker answers 204, so there is nothing to decode.
  public func endSession(minutes: Double) async throws {
    _ = try await send("v1/session/end", body: EndBody(minutes: minutes))
  }
}
