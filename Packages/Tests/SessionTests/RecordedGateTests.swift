import Foundation
import Governor
import Testing
import Transcription

@testable import Session

/// The CI gate over the checked-in Jev recording, and proof it goes red when the governor loses recall.
@Suite struct RecordedGateTests {
  static let gate = try! EvalGate(
    spec: "precision=0.28,recall=0.45,finished-recall=0.55,intrusions=3,collisions=14")

  static let estimate = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("fixtures/synthetic/estimate")

  /// Every fixture replayed through its recorded answers at the config, merged into one report.
  func corpusReport(config: GovernorConfig) async throws -> EvalReport {
    let decoder = JSONDecoder()
    let files = try FileManager.default.contentsOfDirectory(atPath: Self.estimate.path)
      .filter { $0.hasSuffix(".fixture.json") }.sorted()
    #expect(files.count == 10)
    var reports: [EvalReport] = []
    for file in files {
      let name = String(file.dropLast(".fixture.json".count))
      let fixture = try decoder.decode(
        FixtureTranscriber.Fixture.self,
        from: Data(contentsOf: Self.estimate.appendingPathComponent(file)))
      let labels = try decoder.decode(
        Labels.self,
        from: Data(contentsOf: Self.estimate.appendingPathComponent("\(name).labels.json")))
      let answers = try RecordedDecisionProvider(
        contentsOf: Self.estimate.appendingPathComponent("answers/\(name).jsonl"))
      let result = await FixtureDriver.run(
        fixture: fixture, config: config,
        dependencies: .init(
          decisions: answers, compactor: PassthroughCompactor(), phraser: TemplatePhraser()))
      reports.append(EvalReport.score(result, against: labels))
    }
    return EvalReport.merged(reports)
  }

  @Test func shippedConfigClearsTheGate() async throws {
    let report = try await corpusReport(config: .initial)
    #expect(Self.gate.failures(report) == [])
    #expect(report.overall.truePositives == 8)
    #expect(report.overall.falseNegatives == 9)
  }

  @Test func zeroingACueWeightDropsRecallUnderTheFloor() async throws {
    var config = GovernorConfig.initial
    config.cueWeights["trailsOff"] = 0
    let report = try await corpusReport(config: config)
    let failures = Self.gate.failures(report)
    #expect(failures.count == 1)
    #expect(failures.first?.hasPrefix("recall 0.41 is under the 0.45 floor") == true)
  }
}

@Suite struct EvalGateTests {
  func report(precision: (Int, Int), finished: (Int, Int), intrusions: Int, collisions: Int)
    -> EvalReport
  {
    var overall = EvalReport.Kind()
    overall.truePositives = precision.0
    overall.falsePositives = precision.1
    overall.falseNegatives = 17 - precision.0
    var finishedKind = EvalReport.Kind()
    finishedKind.truePositives = finished.0
    finishedKind.falseNegatives = finished.1
    return EvalReport(
      byKind: [:], overall: overall, finished: finishedKind, commands: .init(),
      intrusions: intrusions, collisions: collisions)
  }

  @Test func parsesEveryKeyAndRejectsTheRest() throws {
    let gate = try EvalGate(spec: "precision=0.28,recall=0.45,finished-recall=0.55,intrusions=3")
    #expect(gate == EvalGate(precision: 0.28, recall: 0.45, finishedRecall: 0.55, intrusions: 3))
    #expect(throws: EvalGate.SpecError.unknownKey("lateness")) {
      try EvalGate(spec: "lateness=1")
    }
    #expect(throws: EvalGate.SpecError.badValue("1.5")) { try EvalGate(spec: "recall=1.5") }
    #expect(throws: EvalGate.SpecError.badValue("collisions")) {
      try EvalGate(spec: "collisions")
    }
  }

  @Test func namesEveryBoundCrossedAndNothingElse() throws {
    let gate = try EvalGate(
      spec: "precision=0.28,recall=0.45,finished-recall=0.55,intrusions=3,collisions=14")
    let today = report(precision: (8, 19), finished: (6, 4), intrusions: 3, collisions: 14)
    #expect(gate.failures(today) == [])
    let worse = report(precision: (7, 20), finished: (5, 5), intrusions: 4, collisions: 15)
    #expect(
      gate.failures(worse) == [
        "precision 0.26 is under the 0.28 floor",
        "recall 0.41 is under the 0.45 floor",
        "finished recall 0.50 is under the 0.55 floor",
        "intrusions 4 is over the cap of 3",
        "collisions 15 is over the cap of 14",
      ])
  }

  @Test func noPromptsCountsAsZeroPrecision() throws {
    let gate = try EvalGate(spec: "precision=0.28")
    let silent = report(precision: (0, 0), finished: (0, 0), intrusions: 0, collisions: 0)
    #expect(gate.failures(silent) == ["precision 0.00 is under the 0.28 floor"])
  }
}
