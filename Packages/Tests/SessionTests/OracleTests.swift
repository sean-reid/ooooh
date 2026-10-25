import Foundation
import Testing
import Transcription

@testable import Session

@Suite struct OracleTests {
  @Test func oracleScoresPerfectlyAgainstItsOwnLabels() async throws {
    let decoder = JSONDecoder()
    let fixtureURL = Bundle.module.url(
      forResource: "short", withExtension: "json", subdirectory: "Fixtures")!
    let labelsURL = Bundle.module.url(
      forResource: "short.labels", withExtension: "json", subdirectory: "Fixtures")!
    let fixture = try decoder.decode(
      FixtureTranscriber.Fixture.self, from: Data(contentsOf: fixtureURL))
    let labels = try decoder.decode(Labels.self, from: Data(contentsOf: labelsURL))

    let result = await FixtureDriver.run(
      fixture: fixture, config: .initial,
      dependencies: .init(
        decisions: OracleDecisionProvider(labels: labels), compactor: PassthroughCompactor(),
        phraser: TemplatePhraser()))
    let report = EvalReport.score(result, against: labels)

    #expect(report.overall.precision == 1)
    #expect(report.overall.recall == 1)
    #expect(report.overall.medianLateness == 0)
    #expect(report.finished.precision == 1)
    #expect(report.finished.recall == 1)
    guard case .ended(let at, let byUser)? = result.records.last else {
      Issue.record("session did not end")
      return
    }
    #expect(byUser == false)
    #expect(at >= 87.8 + 30)
  }
}

@Suite struct OracleCommandTests {
  @Test func oracleIssuesCommandsFromLabelsAndWrapUpEndsTheSession() async throws {
    let decoder = JSONDecoder()
    let fixture = try decoder.decode(
      FixtureTranscriber.Fixture.self,
      from: Data(
        contentsOf: Bundle.module.url(
          forResource: "commands", withExtension: "json", subdirectory: "Fixtures")!))
    let labels = try decoder.decode(
      Labels.self,
      from: Data(
        contentsOf: Bundle.module.url(
          forResource: "commands.labels", withExtension: "json", subdirectory: "Fixtures")!))
    let result = await FixtureDriver.run(
      fixture: fixture, config: .initial,
      dependencies: .init(
        decisions: OracleDecisionProvider(labels: labels), compactor: PassthroughCompactor(),
        phraser: TemplatePhraser()))
    #expect(result.commands.map(\.command) == [.recall, .wrapUp])
    #expect(result.records.last == .ended(at: 25.5, byUser: true))
    let report = EvalReport.score(result, against: labels)
    #expect(report.isPerfect)
    #expect(report.commands.recall == 1)
  }
}
