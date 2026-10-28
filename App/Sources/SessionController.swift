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
import Settings
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
    case idle, starting, downloading, running, ended
    case failed(StartFailure)
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
    /// The Worker's clock as every client in the process learned it. Tests pass their own.
    var clock: WorkerClock = .shared
    /// The listener switches, read at Start. Nil runs with their defaults.
    var settings: AppSettings?
    /// Set to replace the permission check and the engine chain, as the tests do.
    var transcriber: (any LiveTranscriber)?
    /// Hears the Worker's start answer for each session, so the billing store reads the free count.
    var freeSessions: FreeSessions?
    /// The headphone and car buttons, which pause, resume, and end the session while it is the
    /// now-playing app.
    var media: (any MediaControls)?
  }

  private(set) var stage: Stage = .idle
  /// The fraction of the speech model downloaded while the stage is `.downloading`.
  private(set) var downloadProgress: Double = 0
  /// Start to End, less every pause; the time the user sees and is charged for.
  private(set) var timing = SessionTiming()
  private(set) var lastPrompt: String?
  /// Every line delivered so far, with how it went; saved with the session at the end.
  private(set) var lines: [SpokenLine] = []
  private(set) var isOffline = false
  private(set) var quietMode = true
  private(set) var result: SessionResult?
  /// Nil until the session ends.
  private(set) var notes: NotesState?
  private(set) var savedSessionID: UUID?
  /// The saved notes as the screen edits them. Nil without a store or before the notes land.
  private(set) var editor: NotesEditor?
  private(set) var compactions = 0
  /// The Worker's answer for this session. Nil until it answers, and when the start failed.
  private(set) var admission: SessionStart?
  /// The reason of the first 402 the Worker answered in this session, nil while every call
  /// went through.
  private(set) var cutoff: String?
  /// True while the Worker refuses the time this phone signs with, even corrected by its own
  /// clock, so every signed call fails and no prompt comes.
  private(set) var clockRefused = false

  private var measuredLevel: Double?
  private var isHearingSpeech = false
  private var promptPending = false
  private var promptPendingSince: Date?
  private(set) var isSpeaking = false
  private var voice: any PromptSpeaking = SilentSpeaker()
  private var quietOverride: AppSettings.QuietModeOverride = .auto
  private var generator: (any NotesGenerator)?
  private var live: LiveSessionLoop?
  private var microphone: (any LiveTranscriber)?
  /// Hears every spoken line, so the microphone's take on it never reaches the loop.
  private var echo: EchoFilter?
  private var observers: [Task<Void, Never>] = []
  private var delivery: Task<Void, Never>?
  private var deliveringLine: UUID?
  private var writing: Task<Void, Never>?
  private var offlineChange: Task<Void, Never>?
  private var gate: SessionGate?
  private let environment: Environment
  private static let log = Logger(subsystem: "com.seanreid.ooooh", category: "session")
  private static let nowPlayingTitle = "ooooh"

  init(environment: Environment = Environment(workerURL: WorkerURL.fromBundle)) {
    self.environment = environment
  }

  var startedAt: Date? { timing.startedAt }
  /// The moment End was tapped, or the loop ended on its own.
  var endedAt: Date? { timing.endedAt }
  var isPaused: Bool { timing.isPaused }

  var phase: OrbPhase {
    guard stage == .running else { return .resting }
    if isPaused { return .paused }
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
    guard stage == .running, !isPaused else { return 0 }
    return measuredLevel ?? (isHearingSpeech ? 0.65 : 0)
  }

  func elapsed(at now: Date) -> TimeInterval { timing.elapsed(at: now) }

  /// `carrying` seeds the state with an open thread from a past session.
  func start(_ source: Source, carrying thread: OpenThread? = nil) async {
    switch stage {
    case .idle, .failed: break
    case .starting, .downloading, .running, .ended: return
    }
    stage = .starting
    downloadProgress = 0
    do {
      var levels: AsyncStream<Double>?
      let transcriber: any Transcriber
      switch source {
      case .microphone:
        let microphone: any LiveTranscriber
        if let stub = environment.transcriber {
          microphone = stub
        } else {
          try await CapturePermissions.request()
          try environment.audio.activate()
          let meter = AudioLevelMeter()
          levels = meter.levels()
          let locale = Locale.current
          guard let engine = await TranscriptionEngine.available(for: locale) else {
            throw NoTranscriptionEngine(locale: locale)
          }
          microphone = engine.makeTranscriber(locale: locale, audioSink: meter)
        }
        try await start(microphone)
        self.microphone = microphone
        Self.log.info("Transcribing with \(microphone.engine.title, privacy: .public)")
        let filter = EchoFilter(microphone)
        echo = filter
        transcriber = filter
      case .fixture(let url, let speed):
        transcriber = PacedTranscriber(try FixtureTranscriber(contentsOf: url), speed: speed)
      }
      quietOverride = environment.settings?.quietModeOverride ?? .auto
      quietMode = isQuiet(environment.audio.route())

      let clockChanges = environment.clock.changes()
      clockRefused = environment.clock.isRefused
      let assembly = await SessionAssembly.make(
        environment: environment, carrying: thread,
        admitted: { [weak self] start in self?.admitted(start) },
        cutOff: { [weak self] reason in Task { @MainActor in self?.cutoff = reason } })
      gate = assembly.gate
      voice = assembly.voice
      generator = assembly.generator
      let guardian = assembly.guardian
      let config = assembly.config
      let dependencies = assembly.dependencies

      let live = LiveSessionLoop(
        config: config, dependencies: dependencies, transcriber: transcriber, levels: levels,
        offline: guardian.changes())
      self.live = live
      if levels != nil { measuredLevel = 0 }
      timing.start(at: .now)
      stage = .running
      environment.media?.register(MediaCommand.allCases) { [weak self] command in
        Task { await self?.handle(command) }
      }
      environment.media?.setNowPlaying(title: Self.nowPlayingTitle, playing: true)
      if guardian.isOffline { scheduleOffline(true) }
      await live.start()
      observers = [
        Task { for await event in live.events() { await handle(event) } },
        Task {
          for await route in environment.audio.routeChanges() {
            quietMode = isQuiet(route)
          }
        },
        Task { for await refused in clockChanges { clockRefused = refused } },
      ]
    } catch {
      Self.log.error("Start failed: \(String(describing: error), privacy: .public)")
      stage = .failed(StartFailure(error))
      try? environment.audio.deactivate()
    }
  }

  /// Shows the speech model download while the transcriber installs it. The progress stream is
  /// drained before this returns either way, so no late value lands on a stage that has moved on.
  private func start(_ microphone: any LiveTranscriber) async throws {
    let download = Task {
      for await fraction in microphone.downloadProgress() {
        stage = .downloading
        downloadProgress = fraction
      }
    }
    do {
      try await microphone.start()
    } catch {
      await download.value
      throw error
    }
    await download.value
  }

  func end() async {
    guard stage == .running, let live else { return }
    timing.end(at: .now)
    await live.end()
    await observers.first?.value
  }

  /// Stops listening without ending: the line in flight is cut, the governor's clock holds, and
  /// the microphone's clock holds with it, so the pause reads as no time at all to the loop.
  func pause() async {
    guard stage == .running, !isPaused, let live else { return }
    timing.pause(at: .now)
    await cancelDelivery()
    isHearingSpeech = false
    await live.pause(audioTime: echo?.audioTime)
    await microphone?.pause()
    environment.media?.setNowPlaying(title: Self.nowPlayingTitle, playing: false)
    Self.log.info(
      "paused at \(self.elapsed(at: .now), format: .fixed(precision: 1), privacy: .public)")
  }

  /// A microphone that will not restart ends the session, since it would listen to nothing.
  func resume() async {
    guard stage == .running, isPaused, let live else { return }
    do {
      try await microphone?.resume()
    } catch {
      Self.log.error("Resume failed: \(String(describing: error), privacy: .public)")
      await end()
      return
    }
    timing.resume(at: .now)
    await live.resume()
    environment.media?.setNowPlaying(title: Self.nowPlayingTitle, playing: true)
    Self.log.info("resumed")
  }

  private func handle(_ command: MediaCommand) async {
    switch command {
    case .play: await resume()
    case .pause: await pause()
    case .togglePlayPause: await isPaused ? resume() : pause()
    case .stop: await end()
    }
  }

  private func admitted(_ start: SessionStart?) {
    admission = start
    if let start { environment.freeSessions?.record(start) }
  }

  /// Posts the minutes from Start to End after the notes, since the Worker answers nothing for a
  /// session it has closed.
  private func postEnd() {
    guard let gate, admission != nil, !startRefused, let endedAt else { return }
    let minutes = SessionGate.minutes(elapsed(at: endedAt))
    Task {
      do {
        try await gate.end(minutes)
      } catch {
        Self.log.error("Session end failed: \(String(describing: error), privacy: .public)")
      }
    }
  }

  private func isQuiet(_ route: AudioRoute) -> Bool {
    switch quietOverride {
    case .voice: false
    case .quiet: true
    case .auto: !(environment.forceVoice || shouldSpeak(route: route))
    }
  }

  private func handle(_ event: SessionEvent) async {
    switch event {
    case .speechLevel(let level):
      measuredLevel = level
    case .speechStarted:
      isHearingSpeech = true
      if !quietMode, delivery != nil { await cancelDelivery() }
    case .speechEnded:
      isHearingSpeech = false
    case .utterance:
      break
    case .promptArmed:
      promptPending = true
      promptPendingSince = .now
    case .promptCancelled:
      await cancelDelivery()
    case .promptRequested(let kind, let text, let at):
      deliver(text, kind: .intervention(kind), at: at)
    case .askedIfFinished(let at):
      deliver("Done for now?", kind: .finishedQuestion, at: at, quietly: true)
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
  private func deliver(
    _ text: String, kind: SpokenLine.Kind, at: TimeInterval, quietly: Bool = false
  ) {
    if delivery != nil { cutDeliveringLine() }
    delivery?.cancel()
    delivery = nil
    guard !text.isEmpty else {
      promptPending = false
      return
    }
    lastPrompt = text
    let line = SpokenLine(text: text, kind: kind, at: at, spoken: !(quietMode || quietly))
    lines.append(line)
    deliveringLine = line.id
    let since = promptPendingSince.map { Date.now.timeIntervalSince($0) } ?? 0
    let hold = environment.aboutToSpeakHold - .seconds(since)
    delivery = Task {
      if hold > .zero { try? await Task.sleep(for: hold) }
      guard !Task.isCancelled, stage == .running else { return }
      let quiet = quietMode || quietly
      if let index = lines.firstIndex(where: { $0.id == line.id }) {
        lines[index].spoken = !quiet
      }
      let speaker: any PromptSpeaking = quiet ? SilentSpeaker() : voice
      for await event in speaker.speak(text: text) {
        guard !Task.isCancelled else { return }
        switch event {
        case .started:
          promptPending = false
          isSpeaking = true
          if quiet {
            environment.haptic()
            environment.announce(text)
          } else if let echo {
            echo.spoke(text)
            Self.log.info(
              """
              line started audioTime=\(echo.audioTime, format: .fixed(precision: 2), privacy: .public) \
              sessionTime=\(self.elapsed(at: .now), format: .fixed(precision: 2), privacy: .public)
              """)
          }
        case .finished:
          isSpeaking = false
          if !quiet { echo?.finishedSpeaking() }
        }
      }
      guard !Task.isCancelled else { return }
      promptPending = false
      isSpeaking = false
      delivery = nil
      deliveringLine = nil
    }
  }

  private func cutDeliveringLine() {
    guard let id = deliveringLine, let index = lines.firstIndex(where: { $0.id == id }) else {
      return
    }
    lines[index].cut = true
    deliveringLine = nil
  }

  /// Sets or clears the bad mark on a line, here and in the store once the session is saved.
  func markLine(_ lineID: UUID, bad: Bool) {
    guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return }
    lines[index].bad = bad
    Task {
      await writing?.value
      guard savedSessionID != nil, let store = environment.store else { return }
      do {
        try await store.markLine(lineID, bad: bad)
      } catch {
        Self.log.error("Line mark failed: \(String(describing: error), privacy: .public)")
      }
    }
  }

  /// The one path a line stops by, for End, speech in voice mode, and a cancelled arm. The orb
  /// leaves speaking at once, whether the request is still waiting on bytes or the line is playing.
  private func cancelDelivery() async {
    promptPending = false
    promptPendingSince = nil
    let wasSpeaking = isSpeaking
    isSpeaking = false
    guard let delivery else { return }
    cutDeliveringLine()
    self.delivery = nil
    delivery.cancel()
    Self.log.info("prompt cancelled speaking=\(wasSpeaking, privacy: .public)")
    await voice.stop()
    if wasSpeaking { echo?.finishedSpeaking() }
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
    await cancelDelivery()
    offlineChange?.cancel()
    for observer in observers { observer.cancel() }
    self.result = result
    timing.end(at: .now)
    let finals = result.transcript.count(where: \.isFinal)
    Self.log.info(
      "Session ended segments=\(result.transcript.count, privacy: .public) final=\(finals, privacy: .public)"
    )
    isHearingSpeech = false
    stage = .ended
    environment.media?.unregister()
    environment.media?.clearNowPlaying()
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
    let duration = elapsed(at: endedAt ?? .now)
    notes = generator == nil ? .unavailable : .writing
    writing = Task {
      let saved = try? await store?.save(
        result: result, lines: lines, notes: nil, title: "", startedAt: startedAt,
        endedAt: startedAt.addingTimeInterval(duration))
      savedSessionID = saved
      if let generator {
        do {
          let written = try await generator.generate(
            state: result.state, transcript: result.transcript)
          if let store, let saved {
            try? await store.attachNotes(written, to: saved)
            if let detail = try? await store.detail(saved) {
              editor = NotesEditor(store: store, detail: detail)
            }
          }
          notes = .written(written)
        } catch {
          if case ProxyError.clockSkew = error { clockRefused = true }
          notes = .unavailable
        }
      }
      postEnd()
    }
  }
}
