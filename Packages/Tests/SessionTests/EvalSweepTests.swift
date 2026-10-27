import Foundation
import Governor
import Testing

@testable import Session

@Suite struct EvalSweepTests {
  @Test func parsesBarsAndWeightsIntoEveryCombination() throws {
    let sweep = try EvalSweep(spec: "bar=0.8,0.9;trailsOff=1,1.38;hangingQuestion=0")
    #expect(sweep.bars == [0.8, 0.9])
    #expect(
      sweep.weights == [
        .init(name: "trailsOff", values: [1, 1.38]), .init(name: "hangingQuestion", values: [0]),
      ])
    let points = sweep.points
    #expect(points.count == 4)
    #expect(points.first == .init(bar: 0.8, weights: ["trailsOff": 1, "hangingQuestion": 0]))
    #expect(points.last == .init(bar: 0.9, weights: ["trailsOff": 1.38, "hangingQuestion": 0]))
    #expect(points.first?.label == "bar 0.80  hangingQuestion 0  trailsOff 1")
  }

  @Test func aPointWritesOverTheConfigAndLeavesTheRestAlone() throws {
    let point = try #require(EvalSweep(spec: "bar=0.85;trailsOff=1.2").points.first)
    let config = point.applied(to: .initial)
    #expect(config.speak.probability == 0.85)
    #expect(config.cueWeights["trailsOff"] == 1.2)
    #expect(
      config.cueWeights["hangingQuestion"] == GovernorConfig.initial.cueWeights["hangingQuestion"])
    #expect(config.cueKinds == GovernorConfig.initial.cueKinds)
    #expect(config.floor == GovernorConfig.initial.floor)
  }

  @Test func weightsAloneKeepTheConfigsBar() throws {
    let points = try EvalSweep(spec: "unnamedDecision=1,1.125").points
    #expect(points.map(\.bar) == [nil, nil])
    #expect(points.map { $0.applied(to: .initial).speak.probability } == [0.9, 0.9])
  }

  @Test func refusesABadValueAndAnEmptyAxis() {
    #expect(throws: EvalSweep.SpecError.badValue("fast")) { try EvalSweep(spec: "bar=fast") }
    #expect(throws: EvalSweep.SpecError.badValue("-1")) { try EvalSweep(spec: "trailsOff=-1") }
    #expect(throws: EvalSweep.SpecError.badValue("bar")) { try EvalSweep(spec: "bar") }
    #expect(throws: EvalSweep.SpecError.emptyAxis("bar")) { try EvalSweep(spec: "bar=") }
  }
}
