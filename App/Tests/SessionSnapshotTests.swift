import Foundation
import Governor
import Session
import SnapshotTesting
import SwiftUI
import TestSupport
import Testing
import Transcription

@testable import ooooh

/// The real screen over a real controller, each state held still: the microphone is fed by hand,
/// a line is spoken by a speaker that never finishes, and the orb is drawn at one time.
/// Reference PNGs live in __Snapshots__ and are rendered on the iPhone 17 Pro simulator.
@MainActor
@Suite struct SessionSnapshotTests {
  @Test(arguments: [ColorScheme.dark, .light])
  func idle(scheme: ColorScheme) {
    snapshot(SessionController(environment: Environment(workerURL: nil)), scheme: scheme)
  }

  @Test(arguments: [ColorScheme.dark, .light])
  func downloading(scheme: ColorScheme) async {
    let transcriber = DownloadingTranscriber(fractions: [0.5])
    let controller = SessionController(environment: downloadEnvironment(transcriber))
    let starting = Task { await controller.start(.microphone) }
    transcriber.release()
    await wait { controller.stage == .downloading && controller.downloadProgress == 0.5 }

    snapshot(controller, scheme: scheme)

    transcriber.finishDownload()
    await starting.value
    await controller.end()
  }

  /// Quiet mode: the line went through the orb and stays on screen while the speaker talks on.
  @Test(arguments: [ColorScheme.dark, .light])
  func listening(scheme: ColorScheme) async {
    let microphone = HandFedMicrophone()
    let controller = SessionController(environment: environment(microphone))
    await controller.start(.microphone)
    #expect(controller.quietMode)
    microphone.say()
    await wait { controller.lastPrompt != nil && controller.phase == .listening }
    microphone.resume(at: 20)
    await wait { controller.level > 0 }

    snapshot(controller, scheme: scheme)
    await controller.end()
  }

  @Test(arguments: [ColorScheme.dark, .light])
  func aboutToSpeak(scheme: ColorScheme) async {
    let microphone = HandFedMicrophone()
    var environment = environment(microphone)
    environment.aboutToSpeakHold = .seconds(60)
    let controller = SessionController(environment: environment)
    await controller.start(.microphone)
    microphone.say()
    await wait { controller.phase == .aboutToSpeak && controller.lastPrompt != nil }

    snapshot(controller, scheme: scheme)
    await controller.end()
  }

  @Test(arguments: [ColorScheme.dark, .light])
  func speaking(scheme: ColorScheme) async {
    let microphone = HandFedMicrophone()
    var environment = environment(microphone)
    environment.forceVoice = true
    environment.speaker = HeldLine()
    let controller = SessionController(environment: environment)
    await controller.start(.microphone)
    #expect(!controller.quietMode)
    microphone.say()
    await wait { controller.phase == .speaking }

    snapshot(controller, scheme: scheme)
    await controller.end()
  }

  @Test(arguments: [ColorScheme.dark, .light])
  func offline(scheme: ColorScheme) async {
    let microphone = HandFedMicrophone()
    var environment = environment(microphone)
    environment.dependencies = nil
    environment.workerURL = URL(string: "http://worker.invalid")
    environment.session = UnreachableProtocol.session()
    let controller = SessionController(environment: environment)
    await controller.start(.microphone)
    microphone.say()
    await wait { controller.phase == .offline }

    snapshot(controller, scheme: scheme)
    await controller.end()
  }

  /// A microphone session with no Worker, no audio session, and a good moment on the one
  /// utterance, which the template phraser turns into one deepen line. The pauses are short,
  /// so each state arrives within a second of the utterance.
  private func environment(_ microphone: HandFedMicrophone) -> Environment {
    var config = GovernorConfig.initial
    config.warmUp = 0
    config.armingDelay = 0.2
    config.silenceChecks = [0.3, 0.6, 0.9]
    var environment = Environment(workerURL: nil)
    environment.audio = .none
    environment.offlineDelay = .zero
    environment.aboutToSpeakHold = .zero
    environment.config = config
    environment.transcriber = microphone
    environment.dependencies = SessionLoop.Dependencies(
      decisions: ScriptedDecisionProvider { input in
        var answers = JevAnswers.quiet
        if input.recentTranscript.last?.end == HandFedMicrophone.utteranceEnd {
          answers.goodMoment = .init(0.95)
          answers.intervention = .init(.deepen, confidence: 0.9)
        }
        return answers
      }, compactor: PassthroughCompactor(), phraser: TemplatePhraser())
    return environment
  }

  private func snapshot(
    _ controller: SessionController, scheme: ColorScheme, testName: String = #function,
    line: UInt = #line
  ) {
    let image = render(
      SessionView(controller: controller, orbTime: 4.2, elapsed: 754), scheme: scheme)
    assertSnapshot(
      of: image, as: .pixels, named: "402-\(scheme.name)", testName: testName, line: line)
  }

  private typealias Environment = SessionController.Environment
}

/// A live transcriber the test speaks into, so nothing moves between the wait and the picture.
final class HandFedMicrophone: LiveTranscriber, @unchecked Sendable {
  let engine = TranscriptionEngine.speechTranscriber
  let audioTime: TimeInterval = 0
  let input: AsyncStream<TranscriptEvent>.Continuation
  private let stream: AsyncStream<TranscriptEvent>

  init() { (stream, input) = AsyncStream.makeStream() }

  func downloadProgress() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
  func start() async throws {}
  func events() -> AsyncStream<TranscriptEvent> { stream }

  func stop() async {
    input.yield(.ended)
    input.finish()
  }

  static let utteranceEnd: TimeInterval = 0.5

  /// A new utterance opening at `at`: the recognizer reports the start with its first volatile words.
  func resume(at: TimeInterval) {
    input.yield(.speechStarted(at: at))
    input.yield(.segment(Segment(text: "and the other", start: at, end: at + 0.6, isFinal: false)))
  }

  /// One finished utterance, over by `end` on the session clock.
  func say(
    _ text: String = "so the thing I keep coming back to is pricing", from start: TimeInterval = 0,
    to end: TimeInterval = utteranceEnd
  ) {
    input.yield(.speechStarted(at: start))
    input.yield(.segment(Segment(text: text, start: start, end: end, isFinal: true)))
    input.yield(.speechEnded(at: end))
  }
}

/// Starts the line and holds it until stopped, so the orb stays in speaking.
struct HeldLine: PromptSpeaking {
  func speak(text: String) -> AsyncStream<SpeechEvent> {
    AsyncStream { continuation in continuation.yield(.started) }
  }

  func stop() async {}
}
