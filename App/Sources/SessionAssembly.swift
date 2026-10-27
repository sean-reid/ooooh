import Foundation
import Governor
import Notes
import OSLog
import Persistence
import Proxy
import Session
import Settings
import State

/// The pieces one session runs on, built from the environment in the order the controller wires
/// them: the Worker client behind its offline guard, the gate and the admission it answers, the
/// voice, the notes generator, the loop's providers behind their wraps, and the config.
@MainActor
struct SessionAssembly {
  let guardian: OfflineGuard
  let gate: SessionGate?
  let admission: Admission?
  let voice: any PromptSpeaking
  let generator: (any NotesGenerator)?
  let dependencies: SessionLoop.Dependencies
  let config: GovernorConfig

  private static let log = Logger(subsystem: "com.seanreid.ooooh", category: "session")

  /// `admitted` gets the Worker's start answer once it lands, nil when the start failed, and
  /// `cutOff` the reason of the first 402 a later call answers.
  static func make(
    environment: SessionController.Environment, carrying thread: OpenThread?,
    admitted: @escaping @MainActor (SessionStart?) -> Void,
    cutOff: @escaping @Sendable (String) -> Void
  ) async -> SessionAssembly {
    let guardian = OfflineGuard(
      offline: environment.workerURL == nil && environment.dependencies == nil)
    let client = environment.workerURL.map {
      ProxyClient(
        baseURL: $0, session: environment.session, attestor: environment.attestor,
        offline: guardian, clock: environment.clock)
    }
    // The guard watches the provider calls and not the start and end, so a Worker nobody reaches
    // shows offline at the first prompt check.
    let gate =
      environment.gate
      ?? environment.workerURL.map {
        SessionGate.worker(
          ProxyClient(
            baseURL: $0, session: environment.session, attestor: environment.attestor,
            clock: environment.clock))
      }
    let admission = gate.map { gate in
      Admission(start: Task { await admit(gate) }, onCutoff: cutOff)
    }
    if let admission { Task { admitted(await admission.start.value) } }
    let voice: any PromptSpeaking
    if let speaker = environment.speaker {
      voice = speaker
    } else if let client {
      voice = VoiceSpeaker { text in
        let audio = client.speak(text: text)
        return admission?.admit(audio) ?? audio
      }
    } else {
      voice = SilentSpeaker()
    }
    let generator = environment.notesGenerator ?? client.map { OpusNotesGenerator(client: $0) }
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
      config = await fetchConfig(client, timeout: environment.configTimeout)
    }
    if environment.settings?.challengeEnabled == false {
      dependencies = ChallengeFilter(config: config).wrap(dependencies)
    }
    return SessionAssembly(
      guardian: guardian, gate: gate, admission: admission, voice: voice, generator: generator,
      dependencies: dependencies, config: config)
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

  private static func fetchConfig(_ client: ProxyClient?, timeout: Duration) async
    -> GovernorConfig
  {
    guard let client else { return .initial }
    let fetch = Task { try await client.config() }
    let deadline = Task {
      try await Task.sleep(for: timeout)
      fetch.cancel()
    }
    defer { deadline.cancel() }
    return (try? await fetch.value) ?? .initial
  }
}
