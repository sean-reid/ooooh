import Foundation
import Governor
import Session
import State
import TestSupport
import Testing
import Transcription

@testable import Proxy

extension StubbedTransportTests {
  /// The bodies the phone posts, one per route, for the Worker's node project to run through its
  /// validators. Regenerate with `WRITE_REQUEST_FIXTURES=1 swift test --package-path Packages`.
  @Suite struct RequestFixtureTests {
    let client = ProxyClient(
      baseURL: URL(string: "https://ooooh.test")!, session: StubProtocol.session())

    static let requestsDir = URL(filePath: #filePath).deletingLastPathComponent()
      .appending(path: "Fixtures/requests")

    /// The same session as worker/test/upstream.ts, so both suites read one picture.
    static let state = CompactState(
      currentThread: "Whether to rebuild the sync layer or patch the queue.",
      mainIdeas: [.init(id: "sync-rebuild", text: "A rebuild would remove the retry queue.")],
      openQuestions: [.init(id: "who-owns-sync", text: "Who owns the sync layer after the move?")],
      recentTopics: ["sync", "queue"],
      lastIntervention: .init(kind: .clarify, text: "Which part feels least clear?", at: 60))

    static let segments = [
      Segment(
        text: "So the queue keeps retrying and I think that's the actual problem.",
        start: 120, end: 126, isFinal: true),
      Segment(
        text: "Or maybe it's the sync layer, I keep going back and forth on that.",
        start: 127, end: 133, isFinal: true),
    ]

    @Test func decide() async throws {
      let input = CheckInput(
        state: Self.state, recentTranscript: Self.segments,
        signals: Signals(
          now: 135.5, pauseLength: 2.5, speechDensity: 0.6, wordsSoFar: 27, promptsSoFar: 1,
          secondsSincePrompt: 75.5), checkIndex: 0)
      try await compare("decide", reply: Bundle.module.fixture("decide.json")) {
        _ = try await JevDecisionProvider(client: client).decide(input)
      }
    }

    @Test func compact() async throws {
      try await compare("compact", reply: Bundle.module.fixture("compact.json")) {
        _ = try await HaikuCompactor(client: client).compact(
          state: Self.state, transcript: Self.segments)
      }
    }

    /// The same two lines as worker/test/upstream.ts, so both suites read one picture.
    static let said: [CompactState.Intervention] = [
      .init(kind: .clarify, text: "Which part feels least clear?", at: 60),
      .init(
        kind: .deepen, text: "Why does the retry queue matter more than the sync layer?", at: 95),
    ]

    @Test func phrase() async throws {
      try await compare("phrase", reply: Bundle.module.fixture("phrase.json")) {
        _ = try await SonnetPhraser(client: client).phrase(
          .clarify, state: Self.state, recent: Self.segments, said: Self.said)
      }
    }

    @Test func notes() async throws {
      try await compare("notes", reply: Bundle.module.fixture("notes.json")) {
        _ = try await OpusNotesGenerator(client: client).generate(
          state: Self.state, transcript: Self.segments)
      }
    }

    @Test func speak() async throws {
      let line = "Which part feels least clear, the queue or the sync?"
      try await compare("speak", reply: Data([0xff, 0xfb, 0x90, 0x00])) {
        for try await _ in client.speak(text: line) {}
      }
    }

    @Test func sessionStart() async throws {
      try await compare("session-start", reply: Bundle.module.fixture("session-start-free.json")) {
        _ = try await client.startSession()
      }
    }

    /// Runs one call against the stub, then checks the bytes it posted against the file, sorted
    /// and indented so the comparison does not hang on JSONEncoder's key order.
    private func compare(_ route: String, reply: Data, _ send: () async throws -> Void)
      async throws
    {
      StubProtocol.reply = .init(status: 200, chunks: [reply])
      StubProtocol.reset()
      try await send()
      let request = try #require(StubProtocol.seen.withLock { $0.first })
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
      var actual = try encoder.encode(JSONDecoder().decode(JSONValue.self, from: request.bodyBytes))
      actual.append(UInt8(ascii: "\n"))
      let file = Self.requestsDir.appending(path: "\(route).json")
      if ProcessInfo.processInfo.environment["WRITE_REQUEST_FIXTURES"] != nil {
        try FileManager.default.createDirectory(
          at: Self.requestsDir, withIntermediateDirectories: true)
        try actual.write(to: file)
      }
      #expect(actual == (try Data(contentsOf: file)))
    }
  }
}

/// JSON as a value, so a body round-trips through JSONEncoder with sorted keys.
private enum JSONValue: Codable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let bool = try? c.decode(Bool.self) {
      self = .bool(bool)
    } else if let number = try? c.decode(Double.self) {
      self = .number(number)
    } else if let string = try? c.decode(String.self) {
      self = .string(string)
    } else if let array = try? c.decode([JSONValue].self) {
      self = .array(array)
    } else {
      self = .object(try c.decode([String: JSONValue].self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let bool): try c.encode(bool)
    case .number(let number): try c.encode(number)
    case .string(let string): try c.encode(string)
    case .array(let array): try c.encode(array)
    case .object(let object): try c.encode(object)
    }
  }
}
