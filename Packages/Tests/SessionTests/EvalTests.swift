import Foundation
import Governor
import State
import Testing
import Transcription

@testable import Session

@Suite struct EvalTests {
  let transcript = (0..<6).map {
    Segment(text: "u\($0)", start: Double($0) * 10, end: Double($0) * 10 + 5, isFinal: true)
  }

  func result(prompts: [(TimeInterval, InterventionKind)], asks: [TimeInterval] = [])
    -> SessionResult
  {
    var records: [SessionRecord] = prompts.map { .prompt(at: $0.0, kind: $0.1, text: "") }
    records += asks.map { .askedIfFinished(at: $0) }
    return SessionResult(records: records, state: .empty, transcript: transcript)
  }

  @Test func exactHitScoresPerfectly() {
    let labels = Labels(fixture: "t", labels: [.init(utterance: 2, at: 25, kind: "deepen")])
    let report = EvalReport.score(result(prompts: [(25, .deepen)]), against: labels)
    #expect(report.overall.precision == 1)
    #expect(report.overall.recall == 1)
    #expect(report.overall.medianLateness == 0)
    #expect(report.byKind["deepen"]?.truePositives == 1)
  }

  @Test func onePauseLateStillCountsTwoDoesNot() {
    let labels = Labels(fixture: "t", labels: [.init(utterance: 2, at: 25, kind: "deepen")])
    let late1 = EvalReport.score(result(prompts: [(35, .deepen)]), against: labels)
    #expect(late1.overall.truePositives == 1)
    #expect(late1.overall.medianLateness == 1)
    let late2 = EvalReport.score(result(prompts: [(45, .deepen)]), against: labels)
    #expect(late2.overall.truePositives == 0)
    #expect(late2.overall.falsePositives == 1)
    #expect(late2.overall.falseNegatives == 1)
  }

  @Test func wrongKindCountsOverallButNotPerKind() {
    let labels = Labels(fixture: "t", labels: [.init(utterance: 2, at: 25, kind: "deepen")])
    let report = EvalReport.score(result(prompts: [(25, .clarify)]), against: labels)
    #expect(report.overall.truePositives == 1)
    #expect(report.byKind["clarify"]?.truePositives == 1)
    #expect(report.byKind["deepen"]?.falseNegatives == nil)
  }

  @Test func finishedAndLeaveAreScoredSeparately() {
    let labels = Labels(
      fixture: "t",
      labels: [
        .init(utterance: 5, at: 55, kind: Labels.finishedKind),
        .init(utterance: 1, at: 15, kind: Labels.leaveKind),
      ])
    let report = EvalReport.score(
      result(prompts: [(16, .reflect)], asks: [57]), against: labels)
    #expect(report.finished.truePositives == 1)
    #expect(report.overall.falsePositives == 1)
    #expect(report.intrusions == 1)
    #expect(report.summary.contains("finished   p 1.00  r 1.00  late 0.0"))
  }
}
