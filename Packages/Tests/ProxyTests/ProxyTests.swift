import Foundation
import Governor
import State
import Testing

@testable import Proxy

/// Decodes what the Worker emits. The files come from `WRITE_FIXTURES=1 npx vitest run --project node`.
@Suite struct ProxyTests {
  func fixture(_ name: String, _ ext: String) throws -> Data {
    let url = try #require(
      Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }

  @Test func decideDecodesIntoJevAnswers() throws {
    let response = try JSONDecoder().decode(
      JevDecisionProvider.Response.self, from: fixture("decide", "json"))
    #expect(response.questionsVersion == 1)
    #expect(response.usage.jevInputTokens == 412)
    let answers = response.answers
    #expect(answers.goodMoment.probability == 0.82)
    #expect(answers.intervention == .init(.clarify, confidence: 0.71))
    #expect(answers.articulationDifficulty.score == 3.35)
    #expect(answers.articulationDifficulty.unit == 0.5875)
    #expect(answers.momentum.score == 2.8)
    #expect(answers.addressesApp.choice == .none)
  }

  @Test func compactDecodesIntoAPatchThatApplies() throws {
    let response = try JSONDecoder().decode(
      HaikuCompactor.Response.self, from: fixture("compact", "json"))
    #expect(response.patch.mode == .converging)
    #expect(response.patch.add.map(\.list) == [.uncertainties])
    #expect(response.usage == ProviderUsage(inputTokens: 980, outputTokens: 120))
    let next = try CompactState.empty.applying(response.patch)
    #expect(next.uncertainties.map(\.id) == ["queue-or-sync"])
    #expect(next.recentTopics == ["sync", "queue", "retries"])
  }

  @Test func phraseDecodesToOneShortSentence() throws {
    let response = try JSONDecoder().decode(
      SonnetPhraser.Response.self, from: fixture("phrase", "json"))
    #expect(response.text.split(separator: " ").count <= 15)
    #expect(response.text.hasSuffix("?"))
  }

  @Test func phraseStreamParsesDeltasThenDone() async throws {
    let text = String(decoding: try fixture("phrase", "sse"), as: UTF8.self)
    let lines = AsyncStream<String> { continuation in
      for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        continuation.yield(String(line))
      }
      continuation.finish()
    }
    var events: [SonnetPhraser.Event] = []
    for try await event in ServerSentEvents.events(from: lines) {
      if let parsed = try SonnetPhraser.event(from: event) { events.append(parsed) }
    }
    let deltas = events.compactMap { if case .delta(let t) = $0 { t } else { nil } }
    #expect(deltas.count == 10)
    guard case .done(let final) = try #require(events.last) else {
      Issue.record("last event was not done")
      return
    }
    #expect(deltas.joined().trimmingCharacters(in: .whitespaces) == final)
    #expect(final == "Which part feels least clear, the queue or the sync?")
  }
}
