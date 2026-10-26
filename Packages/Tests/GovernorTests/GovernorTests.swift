import Foundation
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

  @Test func weightedCueCanOpenTheGateAndUnknownCuesDoNot() {
    var g = Governor(config: .initial)
    var a = answers(good: 0.2, kind: .summarize)
    a.cues = ["trailsOff": 0.7]
    #expect(abs(g.momentScore(a) - 0.966) < 0.001)
    #expect(g.kind(for: a) == .deepen)
    #expect(g.decide(a, signals: signals(at: 10)) == .prompt(.deepen))
    var unknown = answers(good: 0.2)
    unknown.cues = ["somethingNew": 0.99]
    #expect(g.momentScore(unknown) == 0.2)
    var g2 = Governor(config: .initial)
    #expect(g2.decide(unknown, signals: signals(at: 10)) == .wait)
  }

  @Test func decodesAnswersWithoutCues() throws {
    let json = """
      {"goodMoment":{"probability":0.1},"intervention":{"choice":"deepen","confidence":0.5},
       "articulationDifficulty":{"score":2.5,"confidence":0.4},"momentum":{"score":3,"confidence":0.4},
       "seemsFinished":{"probability":0.05},"addressesApp":{"choice":"none","confidence":0.9}}
      """
    let a = try JSONDecoder().decode(JevAnswers.self, from: Data(json.utf8))
    #expect(a.cues.isEmpty)
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
    #expect(g.decide(answers(good: 0.3), signals: signals(at: 10, pause: 40)) == .wait)
    #expect(g.decide(answers(good: 0.3), signals: signals(at: 60, pause: 90)) == .askIfFinished)
  }

  @Test func asksIfFinishedThenEndsAfterSilence() {
    var g = Governor(config: .initial)
    let done = answers(finished: 0.95)
    #expect(g.decide(done, signals: signals(at: 100, pause: 20)) == .askIfFinished)
    #expect(g.decide(done, signals: signals(at: 110, pause: 30)) == .wait)
    #expect(g.decide(done, signals: signals(at: 131, pause: 51)) == .endSession)
  }

  @Test func aLongSilenceAsksIfFinishedWhateverJevThinks() {
    var g = Governor(config: .initial)
    let talking = answers(finished: 0.05)
    #expect(g.decide(talking, signals: signals(at: 120, pause: 44)) == .wait)
    #expect(g.decide(talking, signals: signals(at: 121, pause: 45)) == .askIfFinished)
    #expect(g.decide(talking, signals: signals(at: 140, pause: 64)) == .wait)
    #expect(g.decide(talking, signals: signals(at: 151, pause: 75)) == .endSession)
  }

  @Test func theSilenceScheduleEndsWithTheLongSilenceCheck() {
    var g = Governor(config: .initial)
    #expect(g.nextCheck(speechEnd: 100) == 105)
    for offset in [5.0, 11, 20] {
      let took = g.takeCheck(now: 100 + offset, speechEnd: 100, utteranceEnded: false)
      #expect(took)
    }
    #expect(g.nextCheck(speechEnd: 100) == 145)
    let early = g.takeCheck(now: 144, speechEnd: 100, utteranceEnded: false)
    #expect(!early)
    let due = g.takeCheck(now: 145, speechEnd: 100, utteranceEnded: false)
    #expect(due)
    #expect(g.nextCheck(speechEnd: 100) == nil)
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

  /// The ticks among `ticks` that take a silence check after speech ended at `speechEnd`.
  func fired(_ g: inout Governor, speechEnd: Double, ticks: [Double]) -> [Double] {
    ticks.filter { g.takeCheck(now: $0, speechEnd: speechEnd, utteranceEnded: false) }
  }

  @Test func silenceChecksFollowTheScheduleOnceEach() {
    var g = Governor(config: .initial)
    let utterance = g.takeCheck(now: 10, speechEnd: 10, utteranceEnded: true)
    #expect(utterance)
    #expect(g.nextCheck(speechEnd: 10) == 15)
    let took = fired(&g, speechEnd: 10, ticks: [14.9, 15, 15, 21, 30, 30, 55, 55, 600])
    #expect(took == [15, 21, 30, 55])
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
    #expect(g.nextCheck(speechEnd: 0) == 45)
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
    config.longSilence = 6
    var g = Governor(config: config)
    _ = g.takeCheck(now: 0, speechEnd: 0, utteranceEnded: true)
    #expect(g.nextCheck(speechEnd: 0) == 1)
    #expect(fired(&g, speechEnd: 0, ticks: [2, 3, 4]) == [2, 3])
    #expect(g.nextCheck(speechEnd: 0) == 6)
    #expect(fired(&g, speechEnd: 0, ticks: [6, 7]) == [6])
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
