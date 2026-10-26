import Foundation
import Governor
import Session
import Testing
import Transcription

@testable import ooooh

/// A live transcriber whose start downloads a model one step at a time. Each `release()` yields
/// the next fraction; `finishDownload()` lets `start()` return, or throw `failure`.
final class DownloadingTranscriber: LiveTranscriber, @unchecked Sendable {
  let engine = TranscriptionEngine.speechTranscriber
  private let fractions: [Double]
  private let failure: (any Error)?
  private let downloads: AsyncStream<Double>
  private let download: AsyncStream<Double>.Continuation
  private let steps: AsyncStream<Void>
  private let step: AsyncStream<Void>.Continuation
  private let stream: AsyncStream<TranscriptEvent>
  private let continuation: AsyncStream<TranscriptEvent>.Continuation

  init(fractions: [Double], failing failure: (any Error)? = nil) {
    self.fractions = fractions
    self.failure = failure
    (downloads, download) = AsyncStream.makeStream(of: Double.self)
    (steps, step) = AsyncStream.makeStream(of: Void.self)
    (stream, continuation) = AsyncStream.makeStream(of: TranscriptEvent.self)
  }

  func downloadProgress() -> AsyncStream<Double> { downloads }

  func events() -> AsyncStream<TranscriptEvent> { stream }

  func start() async throws {
    var remaining = fractions[...]
    for await _ in steps {
      guard let next = remaining.popFirst() else { break }
      download.yield(next)
    }
    download.finish()
    if let failure { throw failure }
  }

  func release() { step.yield(()) }

  func finishDownload() { step.finish() }

  func stop() async {
    continuation.yield(.ended)
    continuation.finish()
  }
}

/// A microphone session on `transcriber` with no Worker and no audio session.
@MainActor func downloadEnvironment(_ transcriber: any LiveTranscriber)
  -> SessionController.Environment
{
  var environment = SessionController.Environment(workerURL: nil)
  environment.audio = .none
  environment.speaker = SilentSpeaker()
  environment.offlineDelay = .zero
  environment.config = .initial
  environment.dependencies = SessionLoop.Dependencies(
    decisions: SilentDecisionProvider(), compactor: PassthroughCompactor(),
    phraser: TemplatePhraser())
  environment.transcriber = transcriber
  return environment
}

@MainActor
@Suite struct ModelDownloadTests {
  @Test func theDownloadShowsAsAStageWithItsProgress() async {
    let transcriber = DownloadingTranscriber(fractions: [0, 0.5, 1])
    let controller = SessionController(environment: downloadEnvironment(transcriber))

    let starting = Task { await controller.start(.microphone) }
    await wait { controller.stage == .starting }
    #expect(controller.downloadProgress == 0)
    for fraction in [0.0, 0.5, 1.0] {
      transcriber.release()
      await wait { controller.stage == .downloading && controller.downloadProgress == fraction }
      #expect(controller.phase == .resting)
    }

    transcriber.finishDownload()
    await starting.value
    #expect(controller.stage == .running)
    #expect(controller.downloadProgress == 1)

    await controller.end()
    await wait { controller.stage == .ended }
  }

  @Test func aDownloadThatFailsNamesTheConnection() async {
    let transcriber = DownloadingTranscriber(
      fractions: [0, 0.5],
      failing: SpeechAnalyzerError.downloadFailed(Locale(identifier: "en_US")))
    let controller = SessionController(environment: downloadEnvironment(transcriber))

    let starting = Task { await controller.start(.microphone) }
    transcriber.release()
    transcriber.release()
    await wait { controller.stage == .downloading && controller.downloadProgress == 0.5 }

    transcriber.finishDownload()
    await starting.value
    #expect(controller.stage == .failed(.modelNeedsConnection))
    #expect(controller.phase == .resting)
    #expect(controller.startedAt == nil)
  }

  @Test func aModelAlreadyOnThePhoneSkipsTheStage() async {
    let transcriber = DownloadingTranscriber(fractions: [])
    let controller = SessionController(environment: downloadEnvironment(transcriber))
    transcriber.finishDownload()

    await controller.start(.microphone)
    #expect(controller.stage == .running)
    #expect(controller.downloadProgress == 0)

    await controller.end()
    await wait { controller.stage == .ended }
  }
}
