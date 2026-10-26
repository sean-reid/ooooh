import Audio
import Design
import Foundation
import Governor
import Notes
import OSLog
import Observation
import Persistence
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

  enum NotesState: Equatable {
    case writing
    case written(SessionNotes)
    case unavailable
    /// Nothing was heard, so nothing is saved and Opus is not asked.
    case empty
  }

  struct Environment {
    var workerURL: URL?
    var session: URLSession = .shared
    /// Signs every Worker request when set.
    var attestor: (any Attestor)?
    var audio: AudioAccess = .device
    /// Set to replace the Worker-fed voice, as the tests do.
    var speaker: (any PromptSpeaking)?
    /// Speaks on every route, for hearing the voice path on a simulator.
    var forceVoice = false
    /// Set to replace Opus, as the tests do.
    var notesGenerator: (any NotesGenerator)?
    /// Every session is saved here when set.
    var store: SessionStore?
    var haptic: @MainActor () -> Void = {}
    /// Reads a quiet-mode prompt to VoiceOver, at the moment the haptic lands.
    var announce: @MainActor (String) -> Void = { _ in }
    var offlineDelay: Duration = .seconds(3)
    var aboutToSpeakHold: Duration = .seconds(1)
    var configTimeout: Duration = .seconds(1)
    /// Set to skip the Worker, as the tests do.
    var dependencies: SessionLoop.Dependencies?
    var config: GovernorConfig?
    /// Set to ask it before every source, as the tests and `-free-exhausted 1` do. Every source
    /// otherwise asks the Worker when there is one.
    var gate: SessionGate?
  }

  private(set) var stage: Stage = .idle
  private(set) var startedAt: Date?
  private(set) var endedAt: Date?
  private(set) var lastPrompt: String?
  private(set) var isOffline = false
  private(set) var quietMode = true
  private(set) var result: SessionResult?
  /// Nil until the session ends.
  private(set) var notes: NotesState?
  private(set) var savedSessionID: UUID?
  private(set) var compactions = 0
  /// The Worker's answer for this session. Nil until it answers, and when the start failed.
  private(set) var admission: SessionStart?
  /// The reason of the first 402 the Worker answered in this session, nil while every call
  /// went through.
  private(set) var cutoff: String?

  private var measuredLevel: Double?
  private var isHearingSpeech = false
  private var promptPending = false
  private var promptPendingSince: Date?
  private var isSpeaking = false
  private var voice: any PromptSpeaking = SilentSpeaker()
  private var generator: (any NotesGenerator)?
  private var live: LiveSessionLoop?
  private var observers: [Task<Void, Never>] = []
  private var delivery: Task<Void, Never>?
  private var writing: Task<Void, Never>?
  private var offlineChange: Task<Void, Never>?
  private var admitting: Task<Void, Never>?
  private var gate: SessionGate?
  private let environment: Environment
  private static let log = Logger(subsystem: "com.seanreid.ooooh", category: "session")

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

  /// True once the Worker has refused the session or a call in it, so it listens without prompts.
  var promptsRefused: Bool { startRefused || cutoff != nil }

  /// True once the Worker refused the start, so nothing else is sent to it.
  var startRefused: Bool {
    if case .refused = admission { return true }
    return false
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

  /// `carrying` seeds the state with an open thread from a past session.
  func start(_ source: Source, carrying thread: OpenThread? = nil) async {
    switch stage {
    case .idle, .failed: break
    case .starting, .running, .ended: return
    }
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
        let locale = Locale.current
        guard let engine = await TranscriptionEngine.available(for: locale) else {
          throw NoTranscriptionEngine(locale: locale)
        }
        let microphone = engine.makeTranscriber(locale: locale, audioSink: meter)
        try await microphone.start()
        Self.log.info("Transcribing with \(engine.title, privacy: .public)")
        transcriber = microphone
      case .fixture(let url, let speed):
        transcriber = PacedTranscriber(try FixtureTranscriber(contentsOf: url), speed: speed)
      }
      quietMode = isQuiet(environment.audio.route())

      let guardian = OfflineGuard(
        offline: environment.workerURL == nil && environment.dependencies == nil)
      let client = environment.workerURL.map {
        ProxyClient(
          baseURL: $0, session: environment.session, attestor: environment.attestor,
          offline: guardian)
      }
      // The start and end are bookkeeping; the guard watches the provider calls, as it did before
      // the session routes, so a Worker nobody reaches shows offline at the first prompt check.
      gate =
        environment.gate
        ?? environment.workerURL.map {
          SessionGate.worker(
            ProxyClient(baseURL: $0, session: environment.session, attestor: environment.attestor))
        }
      let admission = gate.map { gate in
        Admission(start: Task { await Self.admit(gate) }) { [weak self] reason in
          Task { @MainActor in self?.cutoff = reason }
        }
      }
      if let admission { admitting = Task { self.admission = await admission.start.value } }
      if let speaker = environment.speaker {
        voice = speaker
      } else if let client {
        voice = VoiceSpeaker { text in
          let audio = client.speak(text: text)
          return admission?.admit(audio) ?? audio
        }
      }
      generator = environment.notesGenerator ?? client.map { OpusNotesGenerator(client: $0) }
      var dependencies =
        environment.dependencies ?? client?.sessionDependencies()
        ?? SessionLoop.Dependencies(
          decisions: SilentDecisionProvider(), compactor: PassthroughCompactor(),
          phraser: TemplatePhraser())
      if let admission { dependencies = admission.wrap(dependencies) }
      if let thread {
        dependencies = CarriedThread(thread).wrap(dependencies)
      }
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
      stage = .failed(StartFailure.message(for: error))
      try? environment.audio.deactivate()
    }
  }

  func end() async {
    guard stage == .running, let live else { return }
    await live.end()
    await observers.first?.value
  }

  /// Nil when the start fails, which leaves the prompts to the offline guard.
  private static func admit(_ gate: SessionGate) async -> SessionStart? {
    do {
      return try await gate.start()
    } catch {
      log.error("Session start failed: \(String(describing: error), privacy: .public)")
      return nil
    }
  }

  /// Posts the wall-clock minutes after the notes, since the Worker answers nothing for a session
  /// it has closed.
  private func postEnd() {
    guard let gate, admission != nil, !startRefused else { return }
    let minutes = (elapsed(at: .now) / 60 * 100).rounded() / 100
    Task {
      do {
        try await gate.end(minutes)
      } catch {
        Self.log.error("Session end failed: \(String(describing: error), privacy: .public)")
      }
    }
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
    case .promptArmed:
      promptPending = true
      promptPendingSince = .now
    case .promptCancelled:
      delivery?.cancel()
      promptPending = false
      promptPendingSince = nil
    case .promptRequested(_, let text, _):
      deliver(text)
    case .askedIfFinished:
      deliver("Done for now?")
    case .compactionApplied:
      compactions += 1
    case .offline(let offline):
      scheduleOffline(offline)
    case .ended(let result):
      await finish(with: result)
    }
  }

  /// Keeps the orb in aboutToSpeak for at least the configured hold since it armed, then speaks.
  /// The orb turns to speaking when sound starts, not when the request goes out.
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
          if quiet {
            environment.haptic()
            environment.announce(text)
          }
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
    let finals = result.transcript.count(where: \.isFinal)
    Self.log.info(
      "Session ended segments=\(result.transcript.count, privacy: .public) final=\(finals, privacy: .public)"
    )
    isSpeaking = false
    promptPending = false
    isHearingSpeech = false
    stage = .ended
    try? environment.audio.deactivate()
    writeNotes(for: result)
  }

  /// Saves the session first, so a failed generation still leaves it in history. A refused
  /// session is saved without notes and Opus is not asked.
  private func writeNotes(for result: SessionResult) {
    guard result.transcript.contains(where: \.isFinal) else {
      notes = .empty
      postEnd()
      return
    }
    let store = environment.store
    let generator = startRefused ? nil : generator
    let startedAt = startedAt ?? .now
    notes = generator == nil ? .unavailable : .writing
    writing = Task {
      let saved = try? await store?.save(
        result: result, notes: nil, title: "", startedAt: startedAt)
      savedSessionID = saved
      if let generator {
        do {
          let written = try await generator.generate(
            state: result.state, transcript: result.transcript)
          if let saved { try? await store?.attachNotes(written, to: saved) }
          notes = .written(written)
        } catch {
          notes = .unavailable
        }
      }
      postEnd()
    }
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
