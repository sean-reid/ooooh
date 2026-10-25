import Foundation
import Governor
import Session
import State
import Testing
import Transcription

@testable import ooooh

@MainActor
@Suite struct SessionControllerTests {
  let shortFixture = Bundle(for: Marker.self).url(forResource: "short", withExtension: "json")!

  final class Marker {}

  /// Records speak and stop in order. A line stays "playing" until stop, two seconds at most.
  @MainActor final class Recorder: PromptSpeaking {
    var calls: [String] = []
    private var stopped = false

    nonisolated func speak(text: String) -> AsyncStream<SpeechEvent> {
      AsyncStream { continuation in
        Task { @MainActor in
          calls.append("speak \(text)")
          stopped = false
          continuation.yield(.started)
          let deadline = ContinuousClock.now + .seconds(2)
          while !stopped, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
          }
          continuation.yield(.finished)
          continuation.finish()
        }
      }
    }

    func stop() async {
      calls.append("stop")
      stopped = true
    }
  }

  /// A good moment on the utterance ending at `end`, quiet otherwise.
  func deps(firing kind: InterventionKind, at end: TimeInterval) -> SessionLoop.Dependencies {
    .init(
      decisions: ScriptedDecisionProvider { input in
        var answers = JevAnswers.quiet
        if input.recentTranscript.last?.end == end {
          answers.goodMoment = .init(0.95)
          answers.intervention = .init(kind, confidence: 0.9)
        }
        return answers
      }, compactor: PassthroughCompactor(), phraser: TemplatePhraser())
  }

  func environment(_ deps: SessionLoop.Dependencies?, speaker: Recorder, haptics: Counter)
    -> SessionController.Environment
  {
    var environment = SessionController.Environment(workerURL: nil)
    environment.audio = .none
    environment.speaker = speaker
    environment.haptic = { haptics.count += 1 }
    environment.offlineDelay = .zero
    environment.aboutToSpeakHold = .milliseconds(200)
    environment.dependencies = deps
    environment.config = .initial
    return environment
  }

  final class Counter { var count = 0 }

  /// Refuses every request at once, so going offline does not depend on the host's network stack.
  final class UnreachableProtocol: URLProtocol {
    static func session() -> URLSession {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [UnreachableProtocol.self]
      return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
    }
    override func stopLoading() {}
  }

  func wait(_ condition: @MainActor () -> Bool, seconds: Double = 10) async {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while !condition(), ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test func reachesEndedWithTheFinalState() async throws {
    let speaker = Recorder()
    let haptics = Counter()
    let controller = SessionController(
      environment: environment(deps(firing: .deepen, at: 14.0), speaker: speaker, haptics: haptics))
    #expect(controller.phase == .resting)

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }

    #expect(controller.stage == .ended)
    #expect(controller.phase == .resting)
    #expect(controller.level == 0)
    let result = try #require(controller.result)
    #expect(result.transcript.count == 17)
    #expect(result.prompts.map(\.at) == [14.0])
    #expect(result.state.currentThread.contains("done for now"))
    #expect(result.state.lastIntervention?.text == "What sits underneath that?")
    #expect(controller.lastPrompt == "What sits underneath that?")
    #expect(controller.elapsed(at: .now) >= 0)
    #expect(controller.elapsed(at: .now) < 5)
  }

  @Test func quietModeSpeaksThroughTheOrbAndOneHaptic() async throws {
    let speaker = Recorder()
    let haptics = Counter()
    let controller = SessionController(
      environment: environment(deps(firing: .deepen, at: 14.0), speaker: speaker, haptics: haptics))

    await controller.start(.fixture(shortFixture, speed: 20))
    #expect(controller.stage == .running)
    #expect(controller.phase == .listening)
    #expect(controller.quietMode)

    await wait { controller.phase == .aboutToSpeak }
    #expect(controller.phase == .aboutToSpeak)
    await wait { controller.phase == .speaking }
    #expect(controller.lastPrompt == "What sits underneath that?")
    #expect(haptics.count == 1)
    await wait { controller.phase != .speaking }
    #expect(speaker.calls.isEmpty)
    await wait { controller.stage == .ended }
    #expect(controller.result?.transcript.count == 17)
  }

  @Test func voiceModeStopsTheLineWhenTheUserSpeaksAgain() async throws {
    let speaker = Recorder()
    let haptics = Counter()
    var environment = environment(
      deps(firing: .deepen, at: 14.0), speaker: speaker, haptics: haptics)
    environment.audio = AudioAccess(
      activate: {}, deactivate: {}, route: { .headphones },
      routeChanges: { AsyncStream { $0.finish() } })
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(shortFixture, speed: 10))
    #expect(!controller.quietMode)
    await wait { controller.phase == .aboutToSpeak }
    await wait { controller.phase == .speaking }
    #expect(speaker.calls == ["speak What sits underneath that?"])
    await wait { speaker.calls.count == 2 }
    #expect(speaker.calls == ["speak What sits underneath that?", "stop"])
    await wait { controller.phase != .speaking }
    #expect(controller.lastPrompt == "What sits underneath that?")
    #expect(haptics.count == 0)
    await wait { controller.stage == .ended }
    #expect(speaker.calls.count == 2)
  }

  @Test func endingByHandKeepsWhatWasHeard() async throws {
    let controller = SessionController(
      environment: environment(
        deps(firing: .deepen, at: -1), speaker: Recorder(), haptics: Counter()))
    await controller.start(.fixture(shortFixture, speed: 1))
    await wait { controller.result == nil && controller.level > 0 }
    #expect(controller.level == 0.65)
    await controller.end()
    #expect(controller.stage == .ended)
    let result = try #require(controller.result)
    #expect(result.transcript.count <= 1)
    #expect(result.records.last == .ended(at: result.transcript.last?.end ?? 0, byUser: true))
  }

  @Test func unreachableWorkerGoesOfflineAndStillEndsWithState() async throws {
    var environment = environment(nil, speaker: Recorder(), haptics: Counter())
    environment.workerURL = URL(string: "http://worker.invalid")
    environment.session = UnreachableProtocol.session()
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(shortFixture, speed: 20))
    await wait { controller.isOffline }
    #expect(controller.isOffline)
    #expect(controller.phase == .offline)
    await wait { controller.stage == .ended }
    let result = try #require(controller.result)
    #expect(result.prompts.isEmpty)
    #expect(result.state.currentThread.contains("done for now"))
    #expect(controller.lastPrompt == nil)
  }
}
