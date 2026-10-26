import Foundation
import State
import Testing

@testable import Governor

@Suite struct GovernorTests {
  /// Answers with the shipped cue for `kind` at `cue`, quiet on every other cue.
  func answers(
    cue: Double = 0.2, kind: InterventionKind = .clarify,
    struggle: Double = 1, momentum: Double = 5, finished: Double = 0.05,
    command: JevAnswers.Command = .none, commandConfidence: Double = 0.1
  ) -> JevAnswers {
    JevAnswers(
      articulationDifficulty: .init(struggle, confidence: 0.8),
      momentum: .init(momentum, confidence: 0.8),
      seemsFinished: .init(finished),
      addressesApp: .init(command, confidence: commandConfidence),
      cues: [GovernorConfig.initial.cue(for: kind)!: cue])
  }

  func signals(at now: Double, pause: Double = 2.5, density: Double = 0.8) -> Signals {
    Signals(now: now, pauseLength: pause, speechDensity: density)
  }

  @Test func theStrongestWeightedCueNamesTheKind() {
    var g = Governor(config: .initial)
    var a = answers(cue: 0.7, kind: .deepen)
    a.cues["threadShift"] = 0.95
    let moment = g.moment(a)
    #expect(moment?.kind == .deepen)
    #expect(abs((moment?.score ?? 0) - 0.966) < 0.001)
    #expect(g.decide(a, signals: signals(at: 10)) == .prompt(.deepen))
  }

  @Test func everyKindHasACueAndTheOracleCueClearsTheBar() {
    for kind in InterventionKind.allCases {
      var g = Governor(config: .initial)
      #expect(g.decide(answers(cue: 0.99, kind: kind), signals: signals(at: 10)) == .prompt(kind))
    }
  }

  @Test func unknownAndUnweightedCuesNeverOpenTheGate() {
    var config = GovernorConfig.initial
    config.cueWeights["untestedClaim"] = nil
    var g = Governor(config: config)
    var a = answers()
    a.cues = ["somethingNew": 0.99, "untestedClaim": 0.99]
    #expect(g.moment(a) == nil)
    #expect(g.decide(a, signals: signals(at: 10)) == .wait)
  }

  @Test func decodesAnswersWithoutCuesAndIgnoresRetiredQuestions() throws {
    let json = """
      {"goodMoment":{"probability":0.1},"intervention":{"choice":"deepen","confidence":0.5},
       "articulationDifficulty":{"score":2.5,"confidence":0.4},"momentum":{"score":3,"confidence":0.4},
       "seemsFinished":{"probability":0.05},"addressesApp":{"choice":"none","confidence":0.9}}
      """
    let a = try JSONDecoder().decode(JevAnswers.self, from: Data(json.utf8))
    #expect(a.cues.isEmpty)
    #expect(a.momentum.score == 3)
  }

  @Test func waitsWhenFlowing() {
    var g = Governor(config: .initial)
    #expect(g.decide(answers(), signals: signals(at: 10)) == .wait)
  }

  @Test func promptsOnACueThenHonoursFloor() {
    var g = Governor(config: .initial)
    let a = answers(cue: 0.9, kind: .deepen)
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
    let stuck = answers(cue: 0.9, struggle: 5, momentum: 1)
    #expect(g.decide(stuck, signals: signals(at: 0, density: 0)) == .prompt(.clarify))
    #expect(g.decide(stuck, signals: signals(at: 31, density: 0)) == .prompt(.clarify))
  }

  @Test func silenceAloneNeverPrompts() {
    var g = Governor(config: .initial)
    #expect(g.decide(answers(cue: 0.3), signals: signals(at: 10, pause: 90)) == .wait)
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
    let a = answers(cue: 0.95, command: .wrapUp, commandConfidence: 0.95)
    #expect(g.decide(a, signals: signals(at: 10)) == .command(.wrapUp))
    let unsure = answers(command: .recall, commandConfidence: 0.4)
    #expect(g.decide(unsure, signals: signals(at: 20)) == .wait)
  }

  /// The ticks among `ticks` that take a silence check after speech ended at `speechEnd`.
  func fired(_ g: inout Governor, speechEnd: Double, ticks: [Double]) -> [Double] {
    ticks.filter { g.takeCheck(now: $0, speechEnd: speechEnd, utteranceEnded: false) }
  }

  @Test func silenceChecksFollowTheScheduleOnceEach() {
    var g = Governor(config: .initial)
    let utterance = g.takeCheck(now: 10, speechEnd: 10, utteranceEnded: true)
    #expect(utterance)
    #expect(g.nextCheck(speechEnd: 10) == 15)
    let took = fired(&g, speechEnd: 10, ticks: [14.9, 15, 15, 21, 30, 30, 60, 600])
    #expect(took == [15, 21, 30])
    #expect(g.nextCheck(speechEnd: 10) == nil)
  }

  @Test func aLateTickCoversTheOffsetsItPassed() {
    var g = Governor(config: .initial)
    _ = g.takeCheck(now: 0, speechEnd: 0, utteranceEnded: true)
    #expect(fired(&g, speechEnd: 0, ticks: [12, 14]) == [12])
    #expect(g.nextCheck(speechEnd: 0) == 20)
  }

  @Test func speechRestartsTheSchedule() {
    var g = Governor(config: .initial)
    _ = g.takeCheck(now: 0, speechEnd: 0, utteranceEnded: true)
    #expect(fired(&g, speechEnd: 0, ticks: [2, 5, 11, 20, 23, 35]) == [5, 11, 20])
    #expect(g.nextCheck(speechEnd: 0) == nil)
    let utterance = g.takeCheck(now: 40, speechEnd: 40, utteranceEnded: true)
    #expect(utterance)
    #expect(g.nextCheck(speechEnd: 40) == 45)
    #expect(fired(&g, speechEnd: 40, ticks: [42, 45]) == [45])
  }

  @Test func afterTheFinishedQuestionOnlyTheEndCheckRemains() {
    var g = Governor(config: .initial)
    _ = g.takeCheck(now: 100, speechEnd: 100, utteranceEnded: true)
    let asked = g.decide(answers(finished: 0.95), signals: signals(at: 100, pause: 0))
    #expect(asked == .askIfFinished)
    #expect(g.nextCheck(speechEnd: 100) == 130)
    #expect(fired(&g, speechEnd: 100, ticks: [102, 105, 111, 120, 130]) == [130])
    #expect(g.decide(answers(), signals: signals(at: 130, pause: 30)) == .endSession)

    var late = Governor(config: .initial)
    _ = late.takeCheck(now: 100, speechEnd: 100, utteranceEnded: true)
    _ = late.decide(answers(), signals: signals(at: 100, pause: 0))
    #expect(fired(&late, speechEnd: 100, ticks: [105]) == [105])
    let askedLate = late.decide(answers(finished: 0.95), signals: signals(at: 105, pause: 5))
    #expect(askedLate == .askIfFinished)
    #expect(late.nextCheck(speechEnd: 100) == 135)
  }

  @Test func theScheduleComesFromTheConfig() {
    var config = GovernorConfig.initial
    config.silenceChecks = [1, 3]
    var g = Governor(config: config)
    _ = g.takeCheck(now: 0, speechEnd: 0, utteranceEnded: true)
    #expect(g.nextCheck(speechEnd: 0) == 1)
    #expect(fired(&g, speechEnd: 0, ticks: [2, 3, 4]) == [2, 3])
    #expect(g.nextCheck(speechEnd: 0) == nil)
  }

  @Test func decodesAConfigWithoutTheScheduleToTheDefault() throws {
    let json = """
      {"version":4,"floor":{"min":30,"max":120},"speak":{"probability":0.9,"confidence":0},
       "finished":{"probability":0.6,"confidence":0.7},"command":{"probability":0.9,"confidence":0.7},
       "densityWindow":120,"endSilence":30,"checkPause":2,"minCheckInterval":3}
      """
    let config = try JSONDecoder().decode(GovernorConfig.self, from: Data(json.utf8))
    #expect(config.silenceChecks == [5, 11, 20])
  }
}
