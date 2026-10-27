import Foundation
import Governor
import State
import Testing
import Transcription

@testable import Session

/// The loop counts words and spoken prompts itself and hands them to every check.
@Suite struct SignalCountsTests {
  @Test func checksCarryTheWordsAndPromptsSoFar() async throws {
    let decisions = CapturingDecisions(firingAt: 11)
    let loop = SessionLoop(
      config: .initial,
      dependencies: .init(
        decisions: decisions, compactor: PassthroughCompactor(), phraser: TemplatePhraser()))
    await loop.handle(.segment(Segment(text: "one two three", start: 0, end: 1, isFinal: true)))
    await loop.handle(.segment(Segment(text: "four five", start: 10, end: 11, isFinal: true)))
    await loop.handle(.segment(Segment(text: "six", start: 20, end: 21, isFinal: true)))
    let result = await loop.finish()

    #expect(result.prompts.map(\.at) == [12.5])
    let signals = await decisions.inputs.map(\.signals)
    #expect(signals.map(\.now) == [1, 11, 21])
    #expect(signals.map(\.wordsSoFar) == [3, 5, 6])
    #expect(signals.map(\.promptsSoFar) == [0, 0, 1])
    #expect(signals.map(\.secondsSincePrompt) == [nil, nil, 8.5])
  }

  @Test func aCancelledArmCountsNoPrompt() async throws {
    let decisions = CapturingDecisions(firingAt: 11)
    let loop = SessionLoop(
      config: .initial,
      dependencies: .init(
        decisions: decisions, compactor: PassthroughCompactor(), phraser: TemplatePhraser()))
    await loop.handle(.segment(Segment(text: "one", start: 10, end: 11, isFinal: true)))
    await loop.handle(.segment(Segment(text: "two", start: 12, end: 13, isFinal: true)))
    let result = await loop.finish()

    #expect(result.prompts.isEmpty)
    #expect(result.cancelledArms == [12])
    let last = try #require(await decisions.inputs.last?.signals)
    #expect(last.promptsSoFar == 0)
    #expect(last.secondsSincePrompt == nil)
  }
}
