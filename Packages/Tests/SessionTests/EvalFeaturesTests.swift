import Foundation
import Governor
import Testing
import Transcription

@testable import Session

/// The feature CSV over one synthetic fixture replayed from its recorded answers.
@Suite struct EvalFeaturesTests {
  static let estimate = RecordedGateTests.estimate

  func rows(_ name: String) async throws -> [FeatureRow] {
    let decoder = JSONDecoder()
    let fixture = try decoder.decode(
      FixtureTranscriber.Fixture.self,
      from: Data(contentsOf: Self.estimate.appendingPathComponent("\(name).fixture.json")))
    let labels = try decoder.decode(
      Labels.self,
      from: Data(contentsOf: Self.estimate.appendingPathComponent("\(name).labels.json")))
    let answers = try RecordedDecisionProvider(
      contentsOf: Self.estimate.appendingPathComponent("answers/\(name).jsonl"))
    let signals = SignalRecordingProvider(answers)
    let result = await FixtureDriver.run(
      fixture: fixture, config: .initial,
      dependencies: .init(
        decisions: signals, compactor: PassthroughCompactor(), phraser: TemplatePhraser()))
    var captured: [TimeInterval: Signals] = [:]
    for record in result.records {
      if case .check(let at, _, _, _) = record { captured[at] = await signals.signals(at: at) }
    }
    return FeatureRow.rows(
      fixture: name, result: result, labels: labels, signals: { captured[$0] })
  }

  @Test func oneRowPerCheckWithTheScorersLabel() async throws {
    let rows = try await rows("decision")
    #expect(rows.count == 49)
    #expect(rows.allSatisfy { $0.fixture == "decision" })
    #expect(rows.filter { $0.signals.pauseLength > 0 }.count == 14)

    let labeled = try #require(rows.first { $0.signals.now == 33.323 })
    #expect(labeled.expectation == .speak(kind: "clarify"))
    #expect(labeled.signals.wordsSoFar == 70)
    #expect(labeled.decision == .wait)
    let late = try #require(rows.first { $0.signals.now == 38.323 })
    #expect(late.expectation == .speak(kind: "clarify"))
    #expect(late.signals.pauseLength == 5)

    let spoke = try #require(rows.first { $0.signals.now == 304.607 })
    #expect(spoke.decision == .prompt(.deepen))
    #expect(spoke.expectation == .wait)
    let finished = try #require(rows.first { $0.signals.now == 509.037 })
    #expect(finished.expectation == .finished)
    #expect(rows.last?.expectation == .finished)
    #expect(rows.filter { $0.expectation.name == "speak" }.count == 10)
  }

  @Test func csvCarriesEveryColumnOnEveryRow() async throws {
    let rows = try await rows("decision")
    let lines = FeatureRow.csv(rows).split(separator: "\n")
    #expect(lines.count == 50)
    let header: String =
      "fixture,at,pauseLength,speechDensity,awaitingFinishedReply,wordsSoFar,promptsSoFar,"
      + "secondsSincePrompt,goodMoment,hangingQuestion,trailsOff,unnamedDecision,"
      + "contradictsEarlier,repeatsPoint,momentum,momentumConfidence,articulation,"
      + "articulationConfidence,seemsFinished,intervention,interventionConfidence,decision,"
      + "label,labelKind"
    #expect(String(lines[0]) == header)
    let width = FeatureRow.columns.count
    for line in lines {
      #expect(line.split(separator: ",", omittingEmptySubsequences: false).count == width)
    }
    let fields = lines[3].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    #expect(fields[0] == "decision")
    #expect(fields[1] == "33.323")
    #expect(fields[7] == "")
    #expect(fields[21] == "wait")
    #expect(fields[22] == "speak")
    #expect(fields[23] == "clarify")
  }
}
