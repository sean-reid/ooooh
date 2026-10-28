import Foundation
import Governor
import Persistence
import Proxy
import Session
import TestSupport
import Testing
import Transcription

@testable import ooooh

/// A pause holds the session without ending it: nothing is heard or decided while it lasts, the
/// clock stands still, and the same session carries on after resume.
@MainActor
@Suite struct SessionPauseTests {
  /// Fires a good moment at the first silence check after the hand-fed utterance, so an arm
  /// needs the clock to run; the utterance alone arms nothing.
  func environment(_ microphone: HandFedMicrophone) -> SessionController.Environment {
    var config = GovernorConfig.initial
    config.warmUp = 0
    config.armingDelay = 0.2
    config.silenceChecks = [0.3, 0.6, 0.9]
    var environment = downloadEnvironment(microphone)
    environment.aboutToSpeakHold = .zero
    environment.config = config
    environment.dependencies = SessionLoop.Dependencies(
      decisions: ScriptedDecisionProvider { input in
        var answers = JevAnswers.quiet
        if input.recentTranscript.last?.end == HandFedMicrophone.utteranceEnd,
          input.signals.pauseLength > 0
        {
          answers.goodMoment = .init(0.95)
          answers.intervention = .init(.deepen, confidence: 0.9)
        }
        return answers
      }, compactor: PassthroughCompactor(), phraser: TemplatePhraser())
    return environment
  }

  /// One utterance, returned once the controller has heard it end, so a pause right after it
  /// comes after the loop has it.
  func speak(
    _ text: String = "so the thing I keep coming back to is pricing", from start: TimeInterval = 0,
    to end: TimeInterval = HandFedMicrophone.utteranceEnd, into microphone: HandFedMicrophone,
    heardBy controller: SessionController
  ) async {
    microphone.input.yield(.speechStarted(at: start))
    microphone.input.yield(.segment(Segment(text: text, start: start, end: end, isFinal: true)))
    await wait { controller.level > 0 }
    microphone.input.yield(.speechEnded(at: end))
    await wait { controller.level == 0 }
  }

  @Test func nothingArmsAcrossAPauseAndTheMomentSpeaksAfterResume() async throws {
    let microphone = HandFedMicrophone()
    let controller = SessionController(environment: environment(microphone))
    await controller.start(.microphone)
    await speak(into: microphone, heardBy: controller)
    await controller.pause()
    #expect(controller.isPaused)
    #expect(controller.phase == .paused)
    #expect(controller.level == 0)
    try await Task.sleep(for: .seconds(1.5))
    #expect(controller.lastPrompt == nil)
    #expect(controller.phase == .paused)
    #expect(controller.stage == .running)

    await controller.resume()
    #expect(!controller.isPaused)
    #expect(controller.phase == .listening)
    await wait { controller.lastPrompt == "What sits underneath that?" }
    await wait { controller.phase == .listening }
    await controller.end()

    let result = try #require(controller.result)
    #expect(result.prompts.map(\.at) == [0.8])
    #expect(result.cancelledArms.isEmpty)
    #expect(result.finishedAsks.isEmpty)
    #expect(controller.lines.map(\.text) == ["What sits underneath that?"])
  }

  @Test func aPauseCutsTheLineInFlight() async throws {
    let microphone = HandFedMicrophone()
    var environment = environment(microphone)
    environment.forceVoice = true
    environment.speaker = HeldLine()
    let controller = SessionController(environment: environment)
    await controller.start(.microphone)
    microphone.say()
    await wait { controller.phase == .speaking }

    await controller.pause()
    #expect(controller.phase == .paused)
    #expect(!controller.isSpeaking)
    #expect(controller.lines.map(\.cut) == [true])
    await controller.end()
    #expect(controller.result?.prompts.count == 1)
  }

  /// End from paused: what the microphone said in the pause is gone, what came before stays.
  @Test func whatIsSaidWhilePausedIsNotRecordedAndEndStillWorks() async throws {
    let microphone = HandFedMicrophone()
    let controller = SessionController(environment: downloadEnvironment(microphone))
    await controller.start(.microphone)
    await speak(into: microphone, heardBy: controller)
    await controller.pause()
    microphone.say("this is said to no one", from: 1.0, to: 1.8)

    await controller.end()
    #expect(controller.stage == .ended)
    #expect(controller.phase == .resting)
    #expect(!controller.isPaused)
    let result = try #require(controller.result)
    #expect(result.transcript.map(\.text) == ["so the thing I keep coming back to is pricing"])
    #expect(result.records.last == .ended(at: HandFedMicrophone.utteranceEnd, byUser: true))
    #expect(controller.endedAt != nil)
  }

  @Test func speechAfterResumeIsRecorded() async throws {
    let microphone = HandFedMicrophone()
    let controller = SessionController(environment: downloadEnvironment(microphone))
    await controller.start(.microphone)
    await speak(into: microphone, heardBy: controller)
    await controller.pause()
    await controller.resume()
    await speak("and I am back", from: 1.0, to: 1.8, into: microphone, heardBy: controller)
    await controller.end()
    let result = try #require(controller.result)
    #expect(
      result.transcript.map(\.text) == [
        "so the thing I keep coming back to is pricing", "and I am back",
      ])
  }

  /// A second of pause between Start and End, bracketed on the wall clock on both sides, so the
  /// bound is what the test measured. The row in history and the minutes posted read the same
  /// counted time.
  @Test func theDurationAndTheMinutesPostedLeaveThePauseOut() async throws {
    let host = "paused-minutes"
    GateProtocol.answer(
      host, "/v1/session/start", 200, try Bundle.tests.fixture("session-start-free.json"))
    let store = try SessionStore(configuration: .inMemory)
    let microphone = HandFedMicrophone()
    var environment = downloadEnvironment(microphone)
    environment.clock = WorkerClock()
    let client = ProxyClient(
      baseURL: URL(string: "http://\(host)")!, session: GateProtocol.session(),
      clock: environment.clock)
    environment.gate = .worker(client)
    environment.store = store
    let controller = SessionController(environment: environment)
    let clock = ContinuousClock()

    let beforeStart = clock.now
    await controller.start(.microphone)
    let afterStart = clock.now
    await speak(into: microphone, heardBy: controller)
    let beforePause = clock.now
    await controller.pause()
    let afterPause = clock.now
    let frozen = controller.elapsed(at: .now)
    try await Task.sleep(for: .seconds(1))
    #expect(controller.elapsed(at: .now) == frozen)
    let beforeResume = clock.now
    await controller.resume()
    let afterResume = clock.now
    try await Task.sleep(for: .milliseconds(200))
    let beforeEnd = clock.now
    await controller.end()
    let afterEnd = clock.now

    let ran = controller.elapsed(at: .now)
    let outerPause = seconds(beforePause.duration(to: afterResume))
    let innerPause = seconds(afterPause.duration(to: beforeResume))
    #expect(ran >= seconds(afterStart.duration(to: beforeEnd)) - outerPause)
    #expect(ran <= seconds(beforeStart.duration(to: afterEnd)) - innerPause)
    #expect(innerPause >= 1)
    let endedAt = try #require(controller.endedAt)
    let startedAt = try #require(controller.startedAt)
    #expect(endedAt.timeIntervalSince(startedAt) >= ran + innerPause)
    #expect(controller.elapsed(at: endedAt + 3600) == ran)

    await wait { controller.savedSessionID != nil }
    let duration = try #require(try await store.sessions().first?.duration)
    #expect(duration == ran)
    await wait { GateProtocol.requests(to: host).contains { $0.path == "/v1/session/end" } }
    let end = try #require(GateProtocol.requests(to: host).last { $0.path == "/v1/session/end" })
    let body = try JSONSerialization.jsonObject(with: end.body) as? [String: Double]
    #expect(body?["minutes"] == SessionGate.minutes(ran))
  }

  func seconds(_ duration: Duration) -> TimeInterval {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) + Double(attoseconds) / 1e18
  }

  @Test func theTimingCountsStartToEndLessEveryPause() {
    let start = Date(timeIntervalSinceReferenceDate: 1000)
    var timing = SessionTiming()
    #expect(timing.elapsed(at: start) == 0)
    timing.pause(at: start)
    #expect(!timing.isPaused)

    timing.start(at: start)
    #expect(timing.elapsed(at: start + 10) == 10)
    timing.resume(at: start + 10)
    #expect(timing.elapsed(at: start + 10) == 10)
    timing.pause(at: start + 10)
    #expect(timing.isPaused)
    timing.pause(at: start + 12)
    #expect(timing.elapsed(at: start + 15) == 10)
    timing.resume(at: start + 20)
    #expect(!timing.isPaused)
    #expect(timing.elapsed(at: start + 25) == 15)
    timing.pause(at: start + 30)
    timing.end(at: start + 34)
    #expect(!timing.isPaused)
    #expect(timing.endedAt == start + 34)
    #expect(timing.elapsed(at: start + 34) == 20)
    #expect(timing.elapsed(at: start + 3600) == 20)
    timing.end(at: start + 40)
    #expect(timing.endedAt == start + 34)
    timing.pause(at: start + 40)
    #expect(!timing.isPaused)
  }
}
