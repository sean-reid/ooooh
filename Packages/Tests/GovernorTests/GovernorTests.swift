import State
import Testing

@testable import Governor

@Suite struct GovernorTests {
  func answers(
    good: Double = 0.2, kind: InterventionKind = .clarify, confidence: Double = 0.8,
    struggle: Double = 1, momentum: Double = 5, finished: Double = 0.05,
    command: JevAnswers.Command = .none, commandConfidence: Double = 0.1
  ) -> JevAnswers {
    JevAnswers(
      goodMoment: .init(good),
      intervention: .init(kind, confidence: confidence),
      articulationDifficulty: .init(struggle, confidence: 0.8),
      momentum: .init(momentum, confidence: 0.8),
      seemsFinished: .init(finished),
      addressesApp: .init(command, confidence: commandConfidence))
  }

  func signals(at now: Double, pause: Double = 2.5, density: Double = 0.8) -> Signals {
    Signals(now: now, pauseLength: pause, speechDensity: density)
  }

  @Test func waitsWhenFlowing() {
    var g = Governor(config: .initial)
    #expect(g.decide(answers(), signals: signals(at: 10)) == .wait)
  }

  @Test func promptsOnGoodMomentThenHonoursFloor() {
    var g = Governor(config: .initial)
    let a = answers(good: 0.9, kind: .deepen)
    #expect(g.decide(a, signals: signals(at: 10)) == .prompt(.deepen))
    #expect(g.decide(a, signals: signals(at: 40)) == .wait)
    #expect(g.decide(a, signals: signals(at: 10 + 121)) == .prompt(.deepen))
  }

  @Test func floorSlidesWithStruggle() {
    let g = Governor(config: .initial)
    let flowing = g.floor(
      for: answers(struggle: 1, momentum: 5), signals: signals(at: 0, density: 1))
    let stuck = g.floor(for: answers(struggle: 5, momentum: 1), signals: signals(at: 0, density: 0))
    #expect(flowing == 120)
    #expect(stuck == 30)
  }

  @Test func fractionalScoresMapOntoTheUnitRange() {
    #expect(JevAnswers.Score(3.35, confidence: 0.6).unit == 0.5875)
    #expect(JevAnswers.Score(0, confidence: 0.6).unit == 0)
    #expect(JevAnswers.Score(6, confidence: 0.6).unit == 1)
    let g = Governor(config: .initial)
    let partway = g.floor(
      for: answers(struggle: 3, momentum: 3), signals: signals(at: 0, density: 0.5))
    #expect(partway == 75)
  }

  @Test func struggleShortensTheGap() {
    var g = Governor(config: .initial)
    let stuck = answers(good: 0.9, struggle: 5, momentum: 1)
    #expect(g.decide(stuck, signals: signals(at: 0, density: 0)) == .prompt(.clarify))
    #expect(g.decide(stuck, signals: signals(at: 31, density: 0)) == .prompt(.clarify))
  }

  @Test func silenceAloneNeverPrompts() {
    var g = Governor(config: .initial)
    #expect(g.decide(answers(good: 0.3), signals: signals(at: 10, pause: 90)) == .wait)
  }

  @Test func asksIfFinishedThenEndsAfterSilence() {
    var g = Governor(config: .initial)
    let done = answers(finished: 0.95)
    #expect(g.decide(done, signals: signals(at: 100, pause: 20)) == .askIfFinished)
    #expect(g.decide(done, signals: signals(at: 110, pause: 30)) == .wait)
    #expect(g.decide(done, signals: signals(at: 131, pause: 51)) == .endSession)
  }

  @Test func speechAfterFinishedQuestionResetsIt() {
    var g = Governor(config: .initial)
    let done = answers(finished: 0.95)
    #expect(g.decide(done, signals: signals(at: 100, pause: 20)) == .askIfFinished)
    #expect(g.decide(answers(), signals: signals(at: 105, pause: 0.5)) == .wait)
    #expect(g.decide(done, signals: signals(at: 200, pause: 20)) == .askIfFinished)
  }

  @Test func commandsWinWhenConfident() {
    var g = Governor(config: .initial)
    let a = answers(good: 0.95, command: .wrapUp, commandConfidence: 0.95)
    #expect(g.decide(a, signals: signals(at: 10)) == .command(.wrapUp))
    let unsure = answers(command: .recall, commandConfidence: 0.4)
    #expect(g.decide(unsure, signals: signals(at: 20)) == .wait)
  }

  @Test func checksOnlyAtBreaksAndNotTooOften() {
    var g = Governor(config: .initial)
    #expect(g.shouldCheck(signals: signals(at: 0, pause: 0.5), utteranceEnded: false) == false)
    #expect(g.shouldCheck(signals: signals(at: 0, pause: 2.5), utteranceEnded: false))
    _ = g.decide(answers(), signals: signals(at: 0))
    #expect(g.shouldCheck(signals: signals(at: 1, pause: 0), utteranceEnded: true))
    #expect(g.shouldCheck(signals: signals(at: 1, pause: 2.5), utteranceEnded: false) == false)
    #expect(g.shouldCheck(signals: signals(at: 3, pause: 2.5), utteranceEnded: false))
  }
}
