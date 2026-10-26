import Audio
import Foundation
import Governor
import Notes
import Persistence
import Proxy
import Session
import Settings
import State
import Synchronization
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

  /// A good moment on the utterance ending at `end`, the speaker sounding finished on the one
  /// ending at `finishedAt`, quiet otherwise. `seen` gets every check's session time.
  func deps(
    firing kind: InterventionKind, at end: TimeInterval, finishedAt: TimeInterval? = nil,
    seen: Seen? = nil
  ) -> SessionLoop.Dependencies {
    .init(
      decisions: ScriptedDecisionProvider { input in
        seen?.nows.append(input.signals.now)
        var answers = JevAnswers.quiet
        if input.recentTranscript.last?.end == end {
          answers.goodMoment = .init(0.95)
          answers.intervention = .init(kind, confidence: 0.9)
        }
        if input.recentTranscript.last?.end == finishedAt {
          answers.seemsFinished = .init(0.9)
        }
        return answers
      }, compactor: PassthroughCompactor(), phraser: TemplatePhraser())
  }

  func environment(
    _ deps: SessionLoop.Dependencies?, speaker: any PromptSpeaking, haptics: Counter,
    announcements: Lines? = nil
  ) -> SessionController.Environment {
    var environment = SessionController.Environment(workerURL: nil)
    environment.audio = .none
    environment.speaker = speaker
    environment.haptic = { haptics.count += 1 }
    environment.announce = { announcements?.lines.append($0) }
    environment.offlineDelay = .zero
    environment.aboutToSpeakHold = .milliseconds(200)
    environment.dependencies = deps
    environment.config = .initial
    return environment
  }

  final class Counter { var count = 0 }

  let headphones = AudioAccess(
    activate: {}, deactivate: {}, route: { .headphones },
    routeChanges: { AsyncStream { $0.finish() } })

  final class Lines { var lines: [String] = [] }

  /// A fixture session gated through a real `ProxyClient` against `GateProtocol`, answering the
  /// start with `body` for this `host`. With no `deps`, the Worker's own providers run against
  /// the same host.
  func gated(
    _ host: String, answering body: Data, status: Int = 200, deps: SessionLoop.Dependencies?
  ) -> SessionController.Environment {
    GateProtocol.answer(host, "/v1/session/start", status, body)
    var environment = environment(deps, speaker: Recorder(), haptics: Counter())
    environment.clock = WorkerClock()
    let client = ProxyClient(
      baseURL: URL(string: "http://\(host)")!, session: GateProtocol.session(),
      clock: environment.clock)
    environment.gate = .worker(client)
    if deps == nil {
      environment.workerURL = client.baseURL
      environment.session = client.session
    }
    environment.notesGenerator = CannedNotes()
    return environment
  }

  func workerFixture(_ name: String) throws -> Data {
    try Data(
      contentsOf: #require(Bundle(for: Marker.self).url(forResource: name, withExtension: "json")))
  }

  struct CannedNotes: NotesGenerator {
    static let notes = SessionNotes(
      title: "Pricing and the free tier",
      summary: "Cap the prompts, not the sessions.",
      decisions: [NoteItem(id: "cap-prompts", text: "Cap prompts at twenty minutes")],
      openThreads: [NoteItem(id: "free-tier-purpose", text: "What the free tier is for")])

    func generate(state: CompactState, transcript: [Segment]) async throws -> SessionNotes {
      try await Task.sleep(for: .milliseconds(50))
      return Self.notes
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
    #expect(result.prompts.map(\.at) == [15.5])
    #expect(result.state.currentThread.contains("done for now"))
    #expect(result.state.lastIntervention?.text == "What sits underneath that?")
    #expect(controller.lastPrompt == "What sits underneath that?")
    let startedAt = try #require(controller.startedAt)
    let endedAt = try #require(controller.endedAt)
    #expect(endedAt >= startedAt)
    #expect(controller.elapsed(at: startedAt) == endedAt.timeIntervalSince(startedAt))
    #expect(controller.elapsed(at: startedAt + 3600) == endedAt.timeIntervalSince(startedAt))
  }

  @Test func quietModeSpeaksThroughTheOrbAndOneHaptic() async throws {
    let speaker = Recorder()
    let haptics = Counter()
    let announcements = Lines()
    let controller = SessionController(
      environment: environment(
        deps(firing: .deepen, at: 14.0), speaker: speaker, haptics: haptics,
        announcements: announcements))

    await controller.start(.fixture(shortFixture, speed: 20))
    #expect(controller.stage == .running)
    #expect(controller.phase == .listening)
    #expect(controller.quietMode)

    await wait { controller.phase == .aboutToSpeak }
    #expect(controller.phase == .aboutToSpeak)
    await wait { controller.phase == .speaking }
    #expect(controller.lastPrompt == "What sits underneath that?")
    #expect(haptics.count == 1)
    #expect(announcements.lines == ["What sits underneath that?"])
    await wait { controller.phase != .speaking }
    #expect(speaker.calls.isEmpty)
    await wait { controller.stage == .ended }
    #expect(controller.result?.transcript.count == 17)
  }

  @Test func speechBeforeThePauseHoldsCancelsTheArmAndNothingIsSpoken() async throws {
    let speaker = Recorder()
    let haptics = Counter()
    let controller = SessionController(
      environment: environment(deps(firing: .deepen, at: 4.2), speaker: speaker, haptics: haptics))

    await controller.start(.fixture(shortFixture, speed: 2))
    await wait { controller.phase == .aboutToSpeak }
    #expect(controller.phase == .aboutToSpeak)
    await wait { controller.phase == .listening }
    #expect(controller.phase == .listening)
    await controller.end()

    let result = try #require(controller.result)
    #expect(result.prompts.isEmpty)
    #expect(result.cancelledArms == [5.1])
    #expect(controller.lastPrompt == nil)
    #expect(speaker.calls.isEmpty)
    #expect(haptics.count == 0)
  }

  @Test func voiceModeStopsTheLineWhenTheUserSpeaksAgain() async throws {
    let speaker = Recorder()
    let haptics = Counter()
    let announcements = Lines()
    var environment = environment(
      deps(firing: .deepen, at: 3.0), speaker: speaker, haptics: haptics,
      announcements: announcements)
    environment.audio = headphones
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(try realTimeFixture(then: speechAgain), speed: 1))
    #expect(!controller.quietMode)
    await wait { controller.phase == .aboutToSpeak }
    await wait { controller.phase == .speaking }
    #expect(speaker.calls == ["speak What sits underneath that?"])
    await wait { speaker.calls.count == 2 }
    #expect(speaker.calls == ["speak What sits underneath that?", "stop"])
    await wait { controller.phase != .speaking }
    #expect(controller.lastPrompt == "What sits underneath that?")
    #expect(haptics.count == 0)
    #expect(announcements.lines.isEmpty)
    await wait { controller.stage == .ended }
    #expect(speaker.calls.count == 2)
  }

  @Test func endDuringTheFetchCancelsItAndNothingPlays() async throws {
    let transport = VoiceSpeakerTests.HangingTransport()
    let haptics = Counter()
    var environment = environment(
      deps(firing: .deepen, at: 3.0), speaker: VoiceSpeaker(audio: transport.audio),
      haptics: haptics)
    environment.audio = headphones
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(try realTimeFixture(then: anHourOut), speed: 1))
    await wait { transport.requests == ["What sits underneath that?"] }
    #expect(controller.phase == .aboutToSpeak)
    #expect(!controller.isSpeaking)
    await controller.end()
    #expect(controller.stage == .ended)
    #expect(controller.phase == .resting)
    #expect(!controller.isSpeaking)
    await wait { !transport.ended.isEmpty }
    #expect(transport.ended == ["cancelled"])
    #expect(transport.requests.count == 1)
    #expect(haptics.count == 0)
  }

  @Test func speechDuringTheFetchCancelsItAndNothingPlays() async throws {
    let transport = VoiceSpeakerTests.HangingTransport()
    var environment = environment(
      deps(firing: .deepen, at: 3.0), speaker: VoiceSpeaker(audio: transport.audio),
      haptics: Counter())
    environment.audio = headphones
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(try realTimeFixture(then: speechAgain), speed: 1))
    await wait { transport.requests == ["What sits underneath that?"] }
    #expect(controller.phase == .aboutToSpeak)
    await wait { !transport.ended.isEmpty }
    #expect(transport.ended == ["cancelled"])
    #expect(controller.stage == .running)
    #expect(controller.phase == .listening)
    #expect(!controller.isSpeaking)
    await controller.end()
    #expect(transport.requests.count == 1)
    #expect(controller.lastPrompt == "What sits underneath that?")
  }

  @Test func aCancelledArmWhileTheOrbSpeaksReturnsItToListening() async throws {
    let haptics = Counter()
    let controller = SessionController(
      environment: environment(
        deps(firing: .deepen, at: 14.0, finishedAt: 25.5), speaker: Recorder(),
        haptics: haptics))

    await controller.start(.fixture(shortFixture, speed: 20))
    await wait { controller.phase == .speaking }
    let spokeAt = ContinuousClock.now
    await wait { controller.phase != .speaking }
    let left = ContinuousClock.now - spokeAt
    #expect(controller.phase == .listening)
    #expect(controller.stage == .running)
    #expect(left < .seconds(1.4), "the hold ran out before the arm was cancelled, \(left)")
    await wait { controller.stage == .ended }
    let result = try #require(controller.result)
    #expect(result.prompts.map(\.at) == [15.5])
    #expect(result.cancelledArms == [26.3])
    #expect(haptics.count == 1)
  }

  @Test func endingByHandKeepsWhatWasHeard() async throws {
    let controller = SessionController(
      environment: environment(
        deps(firing: .deepen, at: -1), speaker: Recorder(), haptics: Counter()))
    await controller.start(.fixture(shortFixture, speed: 1))
    await wait { controller.result == nil && controller.level > 0 }
    #expect(controller.level == 0.65)
    let startedAt = try #require(controller.startedAt)
    #expect(controller.endedAt == nil)
    #expect(controller.elapsed(at: startedAt) == 0)
    #expect(controller.elapsed(at: startedAt + 90) == 90)
    #expect(controller.elapsed(at: startedAt + 61) == 61)
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

    await controller.start(.fixture(try openEndedFixture(), speed: 50))
    await wait { controller.isOffline && controller.level > 0 }
    let refused = UnreachableProtocol.seen.withLock { $0 }
    #expect(controller.isOffline, "stage \(controller.stage), refused \(refused)")
    #expect(controller.phase == .offline, "stage \(controller.stage), refused \(refused)")
    await controller.end()
    #expect(controller.stage == .ended)
    let result = try #require(controller.result)
    #expect(result.prompts.isEmpty)
    #expect(!result.transcript.isEmpty)
    #expect(!result.state.currentThread.isEmpty)
    #expect(controller.lastPrompt == nil)
    await wait { controller.notes == .unavailable }
    #expect(controller.notes == .unavailable)
  }

  /// The short fixture with a segment an hour out, so the session runs until the test ends it.
  func openEndedFixture() throws -> URL {
    let fixture = try JSONDecoder().decode(
      FixtureTranscriber.Fixture.self, from: Data(contentsOf: shortFixture))
    return try write(fixture.segments + [anHourOut])
  }

  /// Two utterances for speed 1, where the loop's timer runs on the wall clock: the prompt
  /// fires at 3.0 and is due at 4.5, so `then` lands while the line is in flight or after it.
  func realTimeFixture(then next: Segment) throws -> URL {
    try write([
      Segment(
        text: "okay so the thing I keep coming back to is pricing", start: 0, end: 1.0,
        isFinal: true),
      Segment(
        text: "but I don't know if people will pay seven dollars", start: 1.5, end: 3.0,
        isFinal: true),
      next,
    ])
  }

  let speechAgain = Segment(
    text: "like I know the backend costs about twenty cents an hour", start: 5.5, end: 8.0,
    isFinal: true)

  let anHourOut = Segment(text: "and one more thing", start: 3600, end: 3601, isFinal: true)

  func write(_ segments: [Segment]) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("fixture-\(UUID().uuidString).json")
    try JSONEncoder().encode(FixtureTranscriber.Fixture(segments: segments)).write(to: url)
    return url
  }

  @Test func unreachableWorkerStillSavesTheSessionWithoutNotes() async throws {
    let store = try SessionStore(configuration: .inMemory)
    var environment = environment(nil, speaker: Recorder(), haptics: Counter())
    environment.workerURL = URL(string: "http://127.0.0.1:9")
    environment.store = store
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.notes == .unavailable }
    await wait { controller.savedSessionID != nil }
    let saved = try #require(controller.savedSessionID)
    let sessions = try await store.sessions()
    #expect(sessions.map(\.id) == [saved])
    #expect(sessions.first?.title == "")
    #expect(sessions.first?.openThreadCount == 0)
    let detail = try #require(try await store.detail(saved))
    #expect(detail.notes == nil)
    #expect(detail.transcript.count == 17)
    #expect(detail.state?.currentThread.contains("done for now") == true)
  }

  @Test func writesTheNotesAfterTheEnd() async throws {
    var environment = environment(nil, speaker: Recorder(), haptics: Counter())
    environment.notesGenerator = CannedNotes()
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    #expect(controller.notes == .writing)
    await wait { controller.notes != .writing }
    #expect(controller.notes == .written(CannedNotes.notes))
  }

  @Test func savesTheSessionAndAttachesTheNotesWhenTheyArrive() async throws {
    let store = try SessionStore(configuration: .inMemory)
    var environment = environment(nil, speaker: Recorder(), haptics: Counter())
    environment.notesGenerator = CannedNotes()
    environment.store = store
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.notes == .written(CannedNotes.notes) }
    let saved = try #require(controller.savedSessionID)
    let sessions = try await store.sessions()
    #expect(sessions.map(\.id) == [saved])
    #expect(sessions.first?.title == "Pricing and the free tier")
    #expect(sessions.first?.openThreadCount == 1)
    #expect(sessions.first?.duration == controller.elapsed(at: .now))
    #expect(controller.elapsed(at: .now) < 87.8)
    let stored = try #require(try await store.notes(for: saved))
    #expect(stored.title == CannedNotes.notes.title)
    #expect(stored.decisions == CannedNotes.notes.decisions)
    #expect(stored.openThreads == CannedNotes.notes.openThreads)
    #expect(try await store.openThreads(limit: 3).map(\.text) == ["What the free tier is for"])
  }

  @Test func aCarriedThreadReachesTheProvidersAndTheFinalState() async throws {
    let store = try SessionStore(configuration: .inMemory)
    var earlierEnvironment = environment(nil, speaker: Recorder(), haptics: Counter())
    earlierEnvironment.notesGenerator = CannedNotes()
    earlierEnvironment.store = store
    let earlier = SessionController(environment: earlierEnvironment)
    await earlier.start(.fixture(shortFixture, speed: .infinity))
    await wait { earlier.notes == .written(CannedNotes.notes) }
    let thread = try #require(try await store.openThreads(limit: 1).first)

    let seen = Seen()
    let decisions = ScriptedDecisionProvider { input in
      seen.states.append(input.state)
      return .quiet
    }
    var environment = environment(
      .init(decisions: decisions, compactor: PassthroughCompactor(), phraser: TemplatePhraser()),
      speaker: Recorder(), haptics: Counter())
    environment.store = store
    let controller = SessionController(environment: environment)
    await controller.start(.fixture(shortFixture, speed: .infinity), carrying: thread)
    await wait { controller.stage == .ended }

    let first = try #require(seen.states.first)
    #expect(first.currentThread == "What the free tier is for")
    #expect(first.openQuestions.map(\.text) == ["What the free tier is for"])
    let result = try #require(controller.result)
    #expect(result.state.openQuestions.map(\.id) == ["carried-free-tier-purpose"])
    #expect(result.state.currentThread.contains("done for now"))
    await wait { controller.savedSessionID != nil }
    #expect(try await store.sessions().count == 2)
  }

  @Test func aFailedStartLeavesTheOrbRestingAndCanBeTriedAgain() async throws {
    let controller = SessionController(
      environment: environment(nil, speaker: Recorder(), haptics: Counter()))
    let missing = shortFixture.deletingLastPathComponent().appending(path: "missing.json")

    await controller.start(.fixture(missing, speed: .infinity))
    #expect(controller.stage == .failed(.unavailable))
    #expect(controller.phase == .resting)
    #expect(controller.level == 0)
    #expect(controller.startedAt == nil)
    #expect(controller.notes == nil)

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    #expect(controller.result?.transcript.count == 17)
  }

  @Test func aSessionWithNothingHeardIsNeitherSavedNorSentToOpus() async throws {
    let empty = FileManager.default.temporaryDirectory.appending(path: "empty-\(UUID()).json")
    try Data(#"{"segments":[]}"#.utf8).write(to: empty)
    let store = try SessionStore(configuration: .inMemory)
    var environment = environment(nil, speaker: Recorder(), haptics: Counter())
    environment.notesGenerator = CannedNotes()
    environment.store = store
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(empty, speed: .infinity))
    await wait { controller.stage == .ended }
    #expect(controller.notes == .empty)
    #expect(controller.savedSessionID == nil)
    #expect(try await store.sessions().isEmpty)
  }

  @Test func theSettingsLineNamesTheEngineOrTheLanguage() async {
    let line = await SettingsSheet.transcriptionLine(for: Locale(identifier: "en_US"))
    let engines = TranscriptionEngine.allCases.map(\.title)
    #expect(engines.contains(line) || line == "Not available for English")
  }

  /// Listener switches on their own defaults, so no test reads the phone's.
  func settings(challenge: Bool = true, quiet: AppSettings.QuietModeOverride = .auto) throws
    -> AppSettings
  {
    let suite = "controller-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    let settings = AppSettings(defaults: defaults)
    settings.challengeEnabled = challenge
    settings.quietModeOverride = quiet
    return settings
  }

  func routedAudio(_ route: AudioRoute, changes: AsyncStream<AudioRoute>) -> AudioAccess {
    AudioAccess(activate: {}, deactivate: {}, route: { route }, routeChanges: { changes })
  }

  @Test func automaticQuietModeFollowsTheRoute() async throws {
    let (routes, route) = AsyncStream.makeStream(of: AudioRoute.self)
    var environment = environment(
      deps(firing: .deepen, at: -1), speaker: Recorder(), haptics: Counter())
    environment.audio = routedAudio(.speaker, changes: routes)
    environment.settings = try settings(quiet: .auto)
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(try openEndedFixture(), speed: 1))
    #expect(controller.quietMode)
    route.yield(.headphones)
    await wait { !controller.quietMode }
    route.yield(.speaker)
    await wait { controller.quietMode }
    await controller.end()
  }

  @Test func alwaysVoiceSpeaksOnTheSpeaker() async throws {
    let speaker = Recorder()
    let haptics = Counter()
    var environment = environment(
      deps(firing: .deepen, at: 3.0), speaker: speaker, haptics: haptics)
    environment.settings = try settings(quiet: .voice)
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(try realTimeFixture(then: speechAgain), speed: 1))
    #expect(!controller.quietMode)
    await wait { controller.phase == .speaking }
    #expect(speaker.calls.first == "speak What sits underneath that?")
    #expect(haptics.count == 0)
    await wait { controller.stage == .ended }
    #expect(!controller.quietMode)
  }

  @Test func alwaysQuietHoldsThroughARouteChange() async throws {
    let speaker = Recorder()
    let haptics = Counter()
    let announcements = Lines()
    let (routes, route) = AsyncStream.makeStream(of: AudioRoute.self)
    var environment = environment(
      deps(firing: .deepen, at: 14.0), speaker: speaker, haptics: haptics,
      announcements: announcements)
    environment.audio = routedAudio(.headphones, changes: routes)
    environment.settings = try settings(quiet: .quiet)
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(shortFixture, speed: 20))
    #expect(controller.quietMode)
    route.yield(.speaker)
    route.yield(.headphones)
    await wait { controller.phase == .speaking }
    #expect(controller.quietMode)
    #expect(haptics.count == 1)
    #expect(announcements.lines == ["What sits underneath that?"])
    await wait { controller.stage == .ended }
    #expect(speaker.calls.isEmpty)
    #expect(controller.quietMode)
  }

  func armed(_ result: SessionResult) -> [ArmedPrompt] {
    result.records.compactMap {
      if case .promptArmed(_, let kind) = $0 { kind } else { nil }
    }
  }

  @Test func aChallengeArmsNothingWhileTheSwitchIsOff() async throws {
    var environment = environment(
      deps(firing: .challenge, at: 14.0), speaker: Recorder(), haptics: Counter())
    environment.settings = try settings(challenge: false)
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    let result = try #require(controller.result)
    #expect(armed(result).isEmpty)
    #expect(result.prompts.isEmpty)
    #expect(controller.lastPrompt == nil)
    #expect(result.records.contains { if case .check = $0 { true } else { false } })

    var otherKinds = environment
    otherKinds.dependencies = deps(firing: .deepen, at: 14.0)
    let deepening = SessionController(environment: otherKinds)
    await deepening.start(.fixture(shortFixture, speed: .infinity))
    await wait { deepening.stage == .ended }
    #expect(armed(try #require(deepening.result)) == [.intervention(.deepen)])
  }

  @Test func aCueMappedToChallengeArmsNothingWhileTheSwitchIsOff() async throws {
    var config = GovernorConfig.initial
    config.cueWeights = ["pushback": 1]
    config.cueKinds = ["pushback": .challenge]
    let decisions = ScriptedDecisionProvider { input in
      var answers = JevAnswers.quiet
      if input.recentTranscript.last?.end == 14.0 {
        answers.cues = ["pushback": 0.95]
        answers.intervention = .init(.deepen, confidence: 0.9)
      }
      return answers
    }
    var environment = environment(
      .init(decisions: decisions, compactor: PassthroughCompactor(), phraser: TemplatePhraser()),
      speaker: Recorder(), haptics: Counter())
    environment.config = config
    environment.settings = try settings(challenge: false)
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    #expect(armed(try #require(controller.result)).isEmpty)
  }

  @Test func aChallengeArmsWhileTheSwitchIsOn() async throws {
    var environment = environment(
      deps(firing: .challenge, at: 14.0), speaker: Recorder(), haptics: Counter())
    environment.settings = try settings(challenge: true)
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    let result = try #require(controller.result)
    #expect(armed(result) == [.intervention(.challenge)])
    #expect(result.prompts.map(\.kind) == [.challenge])
    #expect(controller.lastPrompt == "What would make that wrong?")
  }

  @Test func aFreeSessionPromptsAndPostsItsMinutesAtTheEnd() async throws {
    let seen = Seen()
    let controller = SessionController(
      environment: gated(
        "free", answering: try workerFixture("session-start-free"),
        deps: deps(firing: .deepen, at: 14.0, seen: seen)))

    await controller.start(.fixture(shortFixture, speed: 20))
    await wait { controller.stage == .ended }
    #expect(controller.admission == .free(remaining: 2, promptMinutes: 20))
    #expect(!controller.promptsRefused)
    #expect(SessionView.status(for: controller) == nil)
    #expect(controller.result?.prompts.map(\.at) == [15.5])
    #expect(seen.nows.contains { $0 >= 60 })

    await wait { GateProtocol.requests(to: "free").count == 2 }
    let requests = GateProtocol.requests(to: "free")
    #expect(requests.map(\.path) == ["/v1/session/start", "/v1/session/end"])
    let end = try JSONSerialization.jsonObject(with: requests[1].body) as? [String: Double]
    let minutes = try #require(end?["minutes"])
    let ran = try #require(controller.endedAt).timeIntervalSince(try #require(controller.startedAt))
    #expect(minutes > 0)
    #expect(minutes == SessionGate.minutes(controller.elapsed(at: .now)))
    #expect(abs(minutes * 60 - ran) <= 0.3, "minutes \(minutes) for \(ran) s")
  }

  @Test func theMinutesPostedRoundToHundredths() {
    #expect(SessionGate.minutes(0) == 0)
    #expect(SessionGate.minutes(3) == 0.05)
    #expect(SessionGate.minutes(61) == 1.02)
    #expect(SessionGate.minutes(90) == 1.5)
    #expect(SessionGate.minutes(3600) == 60)
  }

  /// Speech ends at 1.0 s, the session runs on in silence, and End comes about three seconds in.
  /// The clock brackets Start and End, so the bound is what the test measured, not a guess.
  @Test func theHistoryRowAndTheWorkerGetTheSameMinutesFromStartToEnd() async throws {
    let host = "minutes"
    let store = try SessionStore(configuration: .inMemory)
    var environment = gated(
      host, answering: try workerFixture("session-start-free"), deps: deps(firing: .deepen, at: -1))
    environment.store = store
    let controller = SessionController(environment: environment)
    let fixture = try write([
      Segment(
        text: "okay so the thing I keep coming back to is pricing", start: 0, end: 1.0,
        isFinal: true),
      anHourOut,
    ])

    let clock = ContinuousClock()
    let beforeStart = clock.now
    await controller.start(.fixture(fixture, speed: 1))
    let afterStart = clock.now
    try await Task.sleep(for: .seconds(3))
    let beforeEnd = clock.now
    await controller.end()
    let afterEnd = clock.now
    #expect(controller.stage == .ended)
    #expect(controller.result?.transcript.map(\.end) == [1.0])

    await wait { controller.savedSessionID != nil }
    let duration = try #require(try await store.sessions().first?.duration)
    #expect(duration >= seconds(afterStart.duration(to: beforeEnd)))
    #expect(duration <= seconds(beforeStart.duration(to: afterEnd)))
    #expect(duration == controller.elapsed(at: .now))

    await wait { GateProtocol.requests(to: host).contains { $0.path == "/v1/session/end" } }
    let end = try #require(GateProtocol.requests(to: host).last { $0.path == "/v1/session/end" })
    let body = try JSONSerialization.jsonObject(with: end.body) as? [String: Double]
    let minutes = try #require(body?["minutes"])
    #expect(minutes == SessionGate.minutes(duration))
    #expect(minutes >= 0.05)
  }

  func seconds(_ duration: Duration) -> TimeInterval {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) + Double(attoseconds) / 1e18
  }

  @Test func aRefusedSessionListensWithoutAskingForADecision() async throws {
    let seen = Seen()
    let controller = SessionController(
      environment: gated(
        "refused", answering: try workerFixture("session-start-refused"),
        deps: deps(firing: .deepen, at: 14.0, seen: seen)))

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    #expect(controller.admission == .refused(reason: "free-exhausted"))
    #expect(controller.promptsRefused)
    #expect(
      SessionView.status(for: controller)?.text
        == "listening only, this month's free sessions are used up")
    #expect(SessionView.status(for: controller)?.id == "session.quota")
    #expect(seen.nows.isEmpty)
    #expect(controller.result?.prompts.isEmpty == true)
    #expect(controller.lastPrompt == nil)
    #expect(controller.result?.transcript.count == 17)
    #expect(controller.notes == .unavailable)

    try? await Task.sleep(for: .milliseconds(200))
    #expect(GateProtocol.requests(to: "refused").map(\.path) == ["/v1/session/start"])
  }

  @Test func aRefusedSessionSendsTheWorkerNothingElse() async throws {
    var environment = gated(
      "refused-quiet", answering: try workerFixture("session-start-refused"), deps: nil)
    environment.notesGenerator = nil
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    #expect(controller.admission == .refused(reason: "free-exhausted"))
    #expect(controller.startRefused)
    #expect(controller.notes == .unavailable)
    #expect(controller.result?.prompts.isEmpty == true)
    #expect(controller.result?.state.currentThread.contains("done for now") == true)

    try? await Task.sleep(for: .milliseconds(200))
    #expect(GateProtocol.requests(to: "refused-quiet").map(\.path) == ["/v1/session/start"])
  }

  @Test func aNoSessionAnswerTurnsThePromptsOffAndStillPostsTheEnd() async throws {
    let host = "cutoff"
    GateProtocol.answer(
      host, "/v1/decide", 402, Data(#"{"error":"no-session","reason":"minutes-used"}"#.utf8))
    let controller = SessionController(
      environment: gated(host, answering: try workerFixture("session-start-free"), deps: nil))

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    #expect(controller.admission == .free(remaining: 2, promptMinutes: 20))
    await wait { controller.cutoff != nil }
    #expect(controller.cutoff == "minutes-used")
    #expect(controller.promptsRefused)
    #expect(!controller.startRefused)
    #expect(SessionView.status(for: controller)?.id == "session.quota")
    #expect(controller.result?.prompts.isEmpty == true)
    #expect(controller.result?.state.currentThread.contains("done for now") == true)

    await wait { GateProtocol.requests(to: host).contains { $0.path == "/v1/session/end" } }
    let paths = GateProtocol.requests(to: host).map(\.path)
    #expect(paths.first == "/v1/session/start")
    #expect(paths.filter { $0 == "/v1/decide" }.count == 1)
    #expect(paths.contains("/v1/compact"))
    #expect(paths.last == "/v1/session/end")
  }

  @Test func aClockTheWorkerRefusesShowsItsOwnLineAndPromisesNoNotes() async throws {
    let host = "skewed"
    let stale = Data(#"{"error":"unauthorized","reason":"stale"}"#.utf8)
    for path in ["/v1/decide", "/v1/compact", "/v1/phrase", "/v1/notes", "/v1/session/end"] {
      GateProtocol.answer(host, path, 401, stale)
    }
    var environment = gated(host, answering: stale, status: 401, deps: nil)
    environment.notesGenerator = nil
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.clockRefused }
    #expect(controller.clockRefused)
    #expect(!controller.isOffline)
    #expect(!controller.promptsRefused)
    #expect(SessionView.status(for: controller)?.id == "session.clock")
    #expect(
      SessionView.status(for: controller)?.text
        == "listening only, your phone's clock is off, so your listener can't verify it")

    await wait { controller.stage == .ended }
    await wait { controller.notes == .unavailable }
    #expect(controller.result?.prompts.isEmpty == true)
    #expect(controller.lastPrompt == nil)
    #expect(PendingNotesView.line(for: controller) == PendingNotesView.clockLine)
    #expect(PendingNotesView.clockLine.hasSuffix(PendingNotesView.noNotes))
    #expect(PendingNotesView.offlineLine.hasSuffix(PendingNotesView.noNotes))

    let paths = GateProtocol.requests(to: host).map(\.path)
    #expect(paths.filter { $0 == "/v1/session/start" }.count == 2)
    #expect(paths.filter { $0 == "/v1/notes" }.count == 2)
  }

  @Test func theEndIsPostedAfterTheNotes() async throws {
    let host = "ordered"
    var environment = gated(host, answering: try workerFixture("session-start-free"), deps: nil)
    environment.notesGenerator = nil
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    await wait { GateProtocol.requests(to: host).contains { $0.path == "/v1/session/end" } }
    #expect(controller.notes == .unavailable)
    let paths = GateProtocol.requests(to: host).map(\.path)
    #expect(paths.contains("/v1/notes"))
    #expect(paths.last == "/v1/session/end")
  }

  @Test func aPaidSessionPromptsWithoutACap() async throws {
    let seen = Seen()
    let controller = SessionController(
      environment: gated(
        "paid", answering: try workerFixture("session-start-paid"),
        deps: deps(firing: .deepen, at: 80.6, seen: seen)))

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    #expect(controller.admission == .paid)
    #expect(controller.result?.prompts.map(\.at) == [82.1])
    #expect(seen.nows.contains { $0 >= 60 })
    await wait { GateProtocol.requests(to: "paid").count == 2 }
    #expect(GateProtocol.requests(to: "paid").last?.path == "/v1/session/end")
  }

  @Test func thePromptMinutesStopTheDecisions() async throws {
    let seen = Seen()
    let body = Data(#"{"allowed":true,"free":true,"remainingFree":0,"promptMinutes":1}"#.utf8)
    let controller = SessionController(
      environment: gated(
        "capped", answering: body, deps: deps(firing: .deepen, at: 80.6, seen: seen)))

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    #expect(controller.admission == .free(remaining: 0, promptMinutes: 1))
    #expect(!seen.nows.isEmpty)
    #expect(seen.nows.allSatisfy { $0 < 60 })
    #expect(controller.result?.prompts.isEmpty == true)
    #expect(controller.result?.transcript.count == 17)
  }

  @Test func aFailedStartLeavesThePromptsToTheOfflineGuard() async throws {
    let controller = SessionController(
      environment: gated(
        "down", answering: Data(#"{"error":"internal"}"#.utf8), status: 500,
        deps: deps(firing: .deepen, at: 14.0)))

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    #expect(controller.admission == nil)
    #expect(!controller.promptsRefused)
    #expect(!controller.isOffline)
    #expect(controller.result?.prompts.map(\.at) == [15.5])

    try? await Task.sleep(for: .milliseconds(200))
    #expect(GateProtocol.requests(to: "down").map(\.path) == ["/v1/session/start"])
  }

  @Test func aStartThatCannotReachTheWorkerLeavesTheGuardAlone() async throws {
    var environment = environment(
      deps(firing: .deepen, at: 14.0), speaker: Recorder(), haptics: Counter())
    environment.workerURL = URL(string: "http://worker.invalid")
    environment.session = UnreachableProtocol.session()
    environment.notesGenerator = CannedNotes()
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    #expect(controller.admission == nil)
    #expect(!controller.isOffline)
    #expect(controller.result?.prompts.map(\.at) == [15.5])
    let refused = UnreachableProtocol.seen.withLock { $0 }
    #expect(refused.contains { $0.hasPrefix("/v1/session/start@") }, "\(refused)")
  }

  @Test func aFixtureWithAWorkerOpensASessionAndPostsItsEnd() async throws {
    let host = "demo"
    GateProtocol.answer(host, "/v1/session/start", 200, try workerFixture("session-start-free"))
    var environment = environment(
      deps(firing: .deepen, at: 14.0), speaker: Recorder(), haptics: Counter())
    environment.workerURL = URL(string: "http://\(host)")
    environment.session = GateProtocol.session()
    environment.notesGenerator = CannedNotes()
    let controller = SessionController(environment: environment)

    await controller.start(.fixture(shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    #expect(controller.admission == .free(remaining: 2, promptMinutes: 20))
    #expect(controller.result?.prompts.map(\.at) == [15.5])
    await wait { GateProtocol.requests(to: host).count == 2 }
    #expect(
      GateProtocol.requests(to: host).map(\.path) == ["/v1/session/start", "/v1/session/end"])
  }

  final class Seen: @unchecked Sendable {
    var states: [CompactState] = []
    var nows: [TimeInterval] = []
  }
}
