import Audio
import Foundation
import Governor
import Session
import Testing
import Transcription

@testable import ooooh

/// The real controller and loop on a microphone the test speaks into, with a line that plays
/// until it is stopped. What the microphone hears of the line must neither cut it nor be kept.
@MainActor
@Suite struct EchoFilterControllerTests {
  /// A live transcriber fed by hand, on an audio clock that started `lag` seconds after the
  /// session clock, as a phone's does while the engine warms up. Segment times are audio seconds.
  final class EchoMicrophone: LiveTranscriber, @unchecked Sendable {
    let engine = TranscriptionEngine.speechTranscriber
    let lag: TimeInterval
    let input: AsyncStream<TranscriptEvent>.Continuation
    private let stream: AsyncStream<TranscriptEvent>
    private let started = Date()

    init(lag: TimeInterval = 1.2) {
      self.lag = lag
      (stream, input) = AsyncStream.makeStream()
    }

    var audioTime: TimeInterval { max(0, Date().timeIntervalSince(started) - lag) }

    func downloadProgress() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func start() async throws {}
    func pause() async {}
    func resume() async throws {}
    func events() -> AsyncStream<TranscriptEvent> { stream }

    func stop() async {
      input.yield(.ended)
      input.finish()
    }

    /// One utterance as the recognizer reports it: a start, one volatile segment, the final one, an end.
    func hear(_ text: String, from start: TimeInterval, to end: TimeInterval) {
      input.yield(.speechStarted(at: start))
      input.yield(.segment(Segment(text: text, start: start, end: end - 0.1, isFinal: false)))
      input.yield(.segment(Segment(text: text, start: start, end: end, isFinal: true)))
      input.yield(.speechEnded(at: end))
    }
  }

  /// Reports the line started and keeps it playing until stopped, five seconds at most.
  @MainActor final class PlayingLine: PromptSpeaking {
    private(set) var spoken: [String] = []
    private(set) var stops = 0
    private var stopped = false

    nonisolated func speak(text: String) -> AsyncStream<SpeechEvent> {
      AsyncStream { continuation in
        Task { @MainActor in
          spoken.append(text)
          stopped = false
          continuation.yield(.started)
          let deadline = ContinuousClock.now + .seconds(5)
          while !stopped, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
          }
          continuation.yield(.finished)
          continuation.finish()
        }
      }
    }

    func stop() async {
      stops += 1
      stopped = true
    }
  }

  nonisolated static let utteranceEnd: TimeInterval = 0.5

  /// Headphones, so the line is spoken. A good moment on the first utterance, short pauses, no hold.
  func environment(
    _ microphone: EchoMicrophone, _ speaker: PlayingLine, route: AudioRoute = .headphones
  ) -> SessionController.Environment {
    var config = GovernorConfig.initial
    config.warmUp = 0
    config.armingDelay = 0.2
    config.silenceChecks = [0.3, 0.6, 0.9]
    var environment = SessionController.Environment(workerURL: nil)
    environment.audio = AudioAccess(
      activate: {}, deactivate: {}, route: { route },
      routeChanges: { AsyncStream { $0.finish() } })
    environment.forceVoice = route != .headphones
    environment.speaker = speaker
    environment.offlineDelay = .zero
    environment.aboutToSpeakHold = .zero
    environment.config = config
    environment.transcriber = microphone
    environment.dependencies = SessionLoop.Dependencies(
      decisions: ScriptedDecisionProvider { input in
        var answers = JevAnswers.quiet
        if input.recentTranscript.last?.end == Self.utteranceEnd {
          answers.goodMoment = .init(0.95)
          answers.intervention = .init(.deepen, confidence: 0.9)
        }
        return answers
      }, compactor: PassthroughCompactor(), phraser: TemplatePhraser())
    return environment
  }

  func eventually(
    _ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    let deadline = ContinuousClock.now + .seconds(10)
    while !condition(), ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(10))
    }
    if !condition() {
      Issue.record("the condition did not hold within 10 s", sourceLocation: sourceLocation)
    }
  }

  @Test func theLineHeardBackNeitherCutsItselfNorReachesTheTranscript() async throws {
    let microphone = EchoMicrophone()
    let speaker = PlayingLine()
    let controller = SessionController(environment: environment(microphone, speaker))
    let opening = "so the thing I keep coming back to is pricing"
    let reply = "actually I want to go back to the backend costs"

    await controller.start(.microphone)
    #expect(controller.stage == .running)
    #expect(!controller.quietMode)
    microphone.hear(opening, from: 0, to: Self.utteranceEnd)
    await eventually { controller.phase == .speaking }
    let line = try #require(controller.lastPrompt)
    #expect(speaker.spoken == [line])

    let heardAt = microphone.audioTime + 0.2
    microphone.hear(line, from: heardAt, to: heardAt + 1.2)
    try await Task.sleep(for: .milliseconds(300))
    #expect(controller.isSpeaking)
    #expect(controller.phase == .speaking)
    #expect(speaker.stops == 0)

    let repliedAt = microphone.audioTime + 0.2
    microphone.hear(reply, from: repliedAt, to: repliedAt + 1.5)
    await eventually { speaker.stops == 1 }
    #expect(!controller.isSpeaking)
    #expect(controller.phase == .listening)

    await controller.end()
    await eventually { controller.stage == .ended }
    let result = try #require(controller.result)
    #expect(result.transcript.map(\.text) == [opening, reply])
    #expect(result.prompts.map(\.kind) == [.deepen])
  }

  /// On the speaker the microphone hears the line, misheard, so nothing inside its window cuts
  /// it, not even six unrelated words; the person's words after the line still land.
  @Test func onTheSpeakerNothingHeardDuringTheLineCutsIt() async throws {
    let microphone = EchoMicrophone()
    let speaker = PlayingLine()
    let controller = SessionController(
      environment: environment(microphone, speaker, route: .speaker))
    let opening = "so the thing I keep coming back to is pricing"
    let reply = "actually I want to go back to the backend costs"

    await controller.start(.microphone)
    #expect(!controller.quietMode)
    microphone.hear(opening, from: 0, to: Self.utteranceEnd)
    await eventually { controller.phase == .speaking }

    let misheardAt = microphone.audioTime + 0.2
    microphone.hear("once it's under the table we go back", from: misheardAt, to: misheardAt + 1.5)
    microphone.hear("so the thing I keep", from: 0.1, to: 0.4)
    try await Task.sleep(for: .milliseconds(300))
    #expect(controller.isSpeaking)
    #expect(speaker.stops == 0)

    await speaker.stop()
    await eventually { controller.phase == .listening }
    let repliedAt = microphone.audioTime + 1.5
    microphone.hear(reply, from: repliedAt, to: repliedAt + 1.5)
    await controller.end()
    await eventually { controller.stage == .ended }
    let result = try #require(controller.result)
    #expect(result.transcript.map(\.text) == [opening, reply])
  }
}
