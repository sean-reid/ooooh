import Foundation
import Proxy
import Session
import Testing

@testable import ooooh

/// The pieces the assembly builds for a session with no microphone, and the free count the
/// controller records from the Worker's answer.
@MainActor
@Suite struct SessionAssemblyTests {
  final class Marker {}

  /// Says nothing, and is not the `SilentSpeaker` the assembly falls back to.
  struct Mute: PromptSpeaking {
    func speak(text: String) -> AsyncStream<SpeechEvent> { AsyncStream { $0.finish() } }
    func stop() async {}
  }

  let closedPort = URL(string: "http://127.0.0.1:9")!

  func environment(workerURL: URL? = nil) -> SessionController.Environment {
    var environment = SessionController.Environment(workerURL: workerURL)
    environment.audio = .none
    environment.config = .initial
    environment.offlineDelay = .zero
    return environment
  }

  func make(_ environment: SessionController.Environment) async -> SessionAssembly {
    await SessionAssembly.make(
      environment: environment, carrying: nil, admitted: { _ in }, cutOff: { _ in })
  }

  @Test func withoutAWorkerThereIsNoGateAndTheVoiceIsSilent() async {
    let assembly = await make(environment())
    #expect(assembly.gate == nil)
    #expect(assembly.admission == nil)
    #expect(assembly.voice is SilentSpeaker)
    #expect(assembly.generator == nil)
    #expect(assembly.guardian.isOffline)
    #expect(assembly.config == .initial)
  }

  @Test func aWorkerURLBringsTheGateTheVoiceAndTheNotes() async {
    let assembly = await make(environment(workerURL: closedPort))
    #expect(assembly.gate != nil)
    #expect(assembly.voice is VoiceSpeaker)
    #expect(assembly.generator is OpusNotesGenerator)
    #expect(!assembly.guardian.isOffline)
    #expect(await assembly.admission?.start.value == nil)
  }

  @Test func aGateSetByHandCountsWithoutAWorker() async {
    var environment = environment()
    environment.gate = .exhausted
    let assembly = await make(environment)
    #expect(assembly.gate != nil)
    #expect(assembly.voice is SilentSpeaker)
    #expect(await assembly.admission?.start.value == .refused(reason: "free-exhausted"))
  }

  @Test func aSpeakerInTheEnvironmentReplacesTheWorkerVoice() async {
    var environment = environment(workerURL: closedPort)
    environment.speaker = Mute()
    let assembly = await make(environment)
    #expect(assembly.voice is Mute)
    #expect(await assembly.admission?.start.value == nil)
  }

  @Test func theControllerRecordsTheStartAnswerInTheFreeCount() async throws {
    let fixture = try #require(
      Bundle(for: Marker.self).url(forResource: "short", withExtension: "json"))
    let freeSessions = FreeSessions()
    var environment = environment()
    environment.gate = SessionGate(
      start: { .free(remaining: 2, promptMinutes: 20) }, end: { _ in })
    environment.freeSessions = freeSessions
    let controller = SessionController(environment: environment)
    #expect(freeSessions.remaining == nil)

    await controller.start(.fixture(fixture, speed: .infinity))
    await until { controller.admission != nil }
    #expect(controller.admission == .free(remaining: 2, promptMinutes: 20))
    #expect(freeSessions.remaining == 2)
    await until { controller.stage == .ended }
  }

  func until(
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
}
