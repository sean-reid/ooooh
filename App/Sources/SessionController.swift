import Audio
import Design
import Foundation
import Governor
import Observation
import Proxy
import Session
import State
import Transcription

/// Owns one session from Start to the final state: transcriber, providers,
/// config, audio route, the live loop, and what the screen shows of it.
@MainActor @Observable
final class SessionController {
  enum Source {
    case microphone
    case fixture(URL, speed: Double)
  }

  enum Stage: Equatable {
    case idle, starting, running, ended
    case failed(String)
  }

  struct Environment {
    var workerURL: URL?
    var session: URLSession = .shared
    var audio: AudioAccess = .device
    /// Set to replace the Worker-fed voice, as the tests do.
    var speaker: (any PromptSpeaking)?
    /// Speaks on every route, for hearing the voice path on a simulator.
    var forceVoice = false
    var haptic: @MainActor () -> Void = {}
    var offlineDelay: Duration = .seconds(3)
    var aboutToSpeakHold: Duration = .seconds(1)
    var configTimeout: Duration = .seconds(1)
    /// Set to skip the Worker, as the tests do.
    var dependencies: SessionLoop.Dependencies?
    var config: GovernorConfig?
  }

  private(set) var stage: Stage = .idle
  private(set) var startedAt: Date?
  private(set) var endedAt: Date?
  private(set) var lastPrompt: String?
  private(set) var isOffline = false
  private(set) var quietMode = true
  private(set) var result: SessionResult?
  private(set) var compactions = 0

  private var measuredLevel: Double?
  private var isHearingSpeech = false
  private var promptPending = false
  private var promptPendingSince: Date?
  private var isSpeaking = false
  private var voice: any PromptSpeaking = SilentSpeaker()
  private var live: LiveSessionLoop?
  private var observers: [Task<Void, Never>] = []
  private var delivery: Task<Void, Never>?
  private var offlineChange: Task<Void, Never>?
  private let environment: Environment

  init(environment: Environment = Environment(workerURL: WorkerURL.fromBundle)) {
    self.environment = environment
  }

  var phase: OrbPhase {
    guard stage == .running else { return .resting }
    if isSpeaking { return .speaking }
    if promptPending { return .aboutToSpeak }
    if isOffline { return .offline }
    return .listening
  }

  /// Measured from the microphone when there is one, else high while an utterance is heard.
  var level: Double {
    guard stage == .running else { return 0 }
    return measuredLevel ?? (isHearingSpeech ? 0.65 : 0)
  }

  func elapsed(at now: Date) -> TimeInterval {
    guard let startedAt else { return 0 }
    return (endedAt ?? now).timeIntervalSince(startedAt)
  }

  func start(_ source: Source) async {
    guard stage == .idle else { return }
    stage = .starting
    do {
      var levels: AsyncStream<Double>?
      let transcriber: any Transcriber
      switch source {
      case .microphone:
        try await CapturePermissions.request()
        try environment.audio.activate()
        let meter = AudioLevelMeter()
        levels = meter.levels()
        let microphone = SpeechAnalyzerTranscriber(audioSink: meter)
        try await microphone.start()
        transcriber = microphone
      case .fixture(let url, let speed):
        transcriber = PacedTranscriber(try FixtureTranscriber(contentsOf: url), speed: speed)
      }
      quietMode = isQuiet(environment.audio.route())

      let guardian = OfflineGuard(
        offline: environment.workerURL == nil && environment.dependencies == nil)
      let client = environment.workerURL.map {
        ProxyClient(baseURL: $0, session: environment.session, offline: guardian)
      }
      if let speaker = environment.speaker {
        voice = speaker
      } else if let client {
        voice = VoiceSpeaker(audio: client.speak)
      }
      let dependencies =
        environment.dependencies ?? client?.sessionDependencies()
        ?? SessionLoop.Dependencies(
          decisions: SilentDecisionProvider(), compactor: PassthroughCompactor(),
          phraser: TemplatePhraser())
      let config: GovernorConfig
      if let fixed = environment.config {
        config = fixed
      } else {
        config = await fetchConfig(client)
      }

      let live = LiveSessionLoop(
        config: config, dependencies: dependencies, transcriber: transcriber, levels: levels,
        offline: guardian.changes())
      self.live = live
      if levels != nil { measuredLevel = 0 }
      startedAt = .now
      stage = .running
      if guardian.isOffline { scheduleOffline(true) }
      await live.start()
      observers = [
        Task { for await event in live.events() { await handle(event) } },
        Task {
          for await route in environment.audio.routeChanges() {
            quietMode = isQuiet(route)
          }
        },
      ]
    } catch {
      stage = .failed(error.localizedDescription)
      try? environment.audio.deactivate()
    }
  }

  func end() async {
    guard stage == .running, let live else { return }
    await live.end()
    await observers.first?.value
  }

  private func isQuiet(_ route: AudioRoute) -> Bool {
    !(environment.forceVoice || shouldSpeak(route: route))
  }

  private func fetchConfig(_ client: ProxyClient?) async -> GovernorConfig {
    guard let client else { return .initial }
    let fetch = Task { try await client.config() }
    let deadline = Task {
      try await Task.sleep(for: environment.configTimeout)
      fetch.cancel()
    }
    defer { deadline.cancel() }
    return (try? await fetch.value) ?? .initial
  }

  private func handle(_ event: SessionEvent) async {
    switch event {
    case .speechLevel(let level):
      measuredLevel = level
    case .speechStarted:
      isHearingSpeech = true
      if isSpeaking, !quietMode { await voice.stop() }
    case .speechEnded:
      isHearingSpeech = false
    case .utterance:
      break
    case .promptPending:
      promptPending = true
      promptPendingSince = .now
    case .promptRequested(_, let text, _):
      deliver(text)
    case .askedIfFinished:
      promptPending = true
      promptPendingSince = .now
      deliver("Done for now?")
    case .compactionApplied:
      compactions += 1
    case .offline(let offline):
      scheduleOffline(offline)
    case .ended(let result):
      await finish(with: result)
    }
  }

  /// Holds the orb in aboutToSpeak for at least the configured second, then speaks. The orb
  /// turns to speaking when sound starts, not when the request goes out.
  private func deliver(_ text: String) {
    delivery?.cancel()
    guard !text.isEmpty else {
      promptPending = false
      return
    }
    lastPrompt = text
    let since = promptPendingSince.map { Date.now.timeIntervalSince($0) } ?? 0
    let hold = environment.aboutToSpeakHold - .seconds(since)
    delivery = Task {
      if hold > .zero { try? await Task.sleep(for: hold) }
      guard !Task.isCancelled, stage == .running else { return }
      let quiet = quietMode
      let speaker: any PromptSpeaking = quiet ? SilentSpeaker() : voice
      for await event in speaker.speak(text: text) {
        switch event {
        case .started:
          promptPending = false
          isSpeaking = true
          if quiet { environment.haptic() }
        case .finished:
          isSpeaking = false
        }
      }
      guard !Task.isCancelled else { return }
      promptPending = false
      isSpeaking = false
    }
  }

  private func scheduleOffline(_ offline: Bool) {
    offlineChange?.cancel()
    guard offline != isOffline else { return }
    offlineChange = Task {
      try? await Task.sleep(for: environment.offlineDelay)
      guard !Task.isCancelled else { return }
      isOffline = offline
    }
  }

  private func finish(with result: SessionResult) async {
    delivery?.cancel()
    offlineChange?.cancel()
    if isSpeaking { await voice.stop() }
    for observer in observers { observer.cancel() }
    self.result = result
    endedAt = .now
    isSpeaking = false
    promptPending = false
    isHearingSpeech = false
    stage = .ended
    try? environment.audio.deactivate()
  }
}

/// The audio session as the controller touches it, so tests can run without one.
struct AudioAccess: Sendable {
  var activate: @Sendable () throws -> Void
  var deactivate: @Sendable () throws -> Void
  var route: @Sendable () -> AudioRoute
  var routeChanges: @Sendable () -> AsyncStream<AudioRoute>

  static let device = AudioAccess(
    activate: { try AudioSessionController().activate() },
    deactivate: { try AudioSessionController().deactivate() },
    route: { AudioSessionController().currentRoute },
    routeChanges: { AudioSessionController().routeChanges() })

  static let none = AudioAccess(
    activate: {}, deactivate: {}, route: { .speaker },
    routeChanges: { AsyncStream { $0.finish() } })
}
