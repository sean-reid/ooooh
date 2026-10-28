import Foundation
import Governor
import MediaPlayer
import Session
import TestSupport
import Testing
import Transcription

@testable import ooooh

/// Records what the controller registers and publishes, and fires commands on request.
@MainActor final class RecordingMediaControls: MediaControls {
  var registered: [MediaCommand] = []
  var handler: (@MainActor (MediaCommand) -> Void)?
  /// The title of each publication, nil for a clear, and the rate each one carried.
  var nowPlaying: [String?] = []
  var rates: [Double] = []
  var unregistrations = 0

  func register(_ commands: [MediaCommand], handler: @escaping @MainActor (MediaCommand) -> Void) {
    registered = commands
    self.handler = handler
  }

  func unregister() {
    unregistrations += 1
    handler = nil
  }

  func setNowPlaying(title: String, playing: Bool) {
    nowPlaying.append(title)
    rates.append(playing ? 1 : 0)
  }

  func clearNowPlaying() { nowPlaying.append(nil) }
}

@MainActor
@Suite struct MediaControlsTests {
  let shortFixture = try! Bundle.tests.fixtureURL("short.json")

  func controller(_ media: RecordingMediaControls) -> SessionController {
    var environment = downloadEnvironment(HandFedMicrophone())
    environment.media = media
    return SessionController(environment: environment)
  }

  @Test func startRegistersEveryCommandAndPublishesTheApp() async {
    let media = RecordingMediaControls()
    let controller = controller(media)
    #expect(media.registered.isEmpty)
    #expect(media.nowPlaying.isEmpty)

    await controller.start(.microphone)
    #expect(controller.stage == .running)
    #expect(media.registered == [.play, .pause, .togglePlayPause, .stop])
    #expect(media.nowPlaying == ["ooooh"])
    #expect(media.rates == [1])
    #expect(media.unregistrations == 0)

    await controller.end()
    #expect(controller.stage == .ended)
    #expect(media.unregistrations == 1)
    #expect(media.nowPlaying == ["ooooh", nil])
  }

  @Test func stopEndsTheSession() async throws {
    let media = RecordingMediaControls()
    let controller = controller(media)
    await controller.start(.microphone)
    let handler = try #require(media.handler)

    handler(.stop)
    await wait { controller.stage == .ended }

    #expect(controller.stage == .ended)
    #expect(controller.endedAt != nil)
    #expect(media.unregistrations == 1)
    #expect(media.nowPlaying.last == .some(nil))
  }

  /// Pause and play each do one thing; toggle does whichever the session is not. Every change
  /// republishes the title with the rate the car's display shows.
  @Test(arguments: [
    [MediaCommand.pause, .play], [.togglePlayPause, .togglePlayPause], [.pause, .togglePlayPause],
    [.togglePlayPause, .play],
  ])
  func pauseAndPlayHoldAndReleaseTheSession(_ commands: [MediaCommand]) async throws {
    let media = RecordingMediaControls()
    let controller = controller(media)
    await controller.start(.microphone)
    let handler = try #require(media.handler)

    handler(commands[0])
    await wait { controller.isPaused }
    #expect(controller.stage == .running)
    #expect(controller.phase == .paused)
    #expect(media.rates == [1, 0])
    #expect(media.unregistrations == 0)

    handler(commands[1])
    await wait { !controller.isPaused }
    #expect(controller.stage == .running)
    #expect(controller.phase == .listening)
    #expect(media.rates == [1, 0, 1])
    #expect(media.nowPlaying == ["ooooh", "ooooh", "ooooh"])
    await controller.end()
  }

  @Test func playWhileListeningAndPauseWhilePausedChangeNothing() async throws {
    let media = RecordingMediaControls()
    let controller = controller(media)
    await controller.start(.microphone)
    let handler = try #require(media.handler)

    handler(.play)
    try await Task.sleep(for: .milliseconds(50))
    #expect(!controller.isPaused)
    #expect(media.rates == [1])

    handler(.pause)
    await wait { controller.isPaused }
    handler(.pause)
    try await Task.sleep(for: .milliseconds(50))
    #expect(controller.isPaused)
    #expect(media.rates == [1, 0])
    await controller.end()
  }

  @Test func stopEndsAPausedSession() async throws {
    let media = RecordingMediaControls()
    let controller = controller(media)
    await controller.start(.microphone)
    let handler = try #require(media.handler)
    handler(.pause)
    await wait { controller.isPaused }

    handler(.stop)
    await wait { controller.stage == .ended }

    #expect(controller.stage == .ended)
    #expect(controller.phase == .resting)
    #expect(controller.endedAt != nil)
    #expect(media.unregistrations == 1)
    #expect(media.nowPlaying.last == .some(nil))
  }

  @Test func aFailedStartRegistersNothing() async {
    let media = RecordingMediaControls()
    let transcriber = DownloadingTranscriber(
      fractions: [], failing: NoTranscriptionEngine(locale: .current))
    transcriber.finishDownload()
    var environment = downloadEnvironment(transcriber)
    environment.media = media
    let controller = SessionController(environment: environment)
    await controller.start(.microphone)
    guard case .failed = controller.stage else {
      Issue.record("expected a failed start, got \(controller.stage)")
      return
    }
    #expect(media.registered.isEmpty)
    #expect(media.nowPlaying.isEmpty)
    #expect(media.unregistrations == 0)
  }

  /// The real wrapper against the real centers: the four commands turn on and off with it, and
  /// the title lands in and leaves the Now Playing center.
  @Test func theSystemControlsReachTheCommandAndNowPlayingCenters() {
    let center = MPRemoteCommandCenter.shared()
    let commands = [
      center.playCommand, center.pauseCommand, center.togglePlayPauseCommand, center.stopCommand,
    ]
    let controls = SystemMediaControls()
    controls.register(MediaCommand.allCases) { _ in }
    controls.setNowPlaying(title: "ooooh", playing: true)
    #expect(commands.map(\.isEnabled) == [true, true, true, true])
    let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
    #expect(info?[MPMediaItemPropertyTitle] as? String == "ooooh")
    #expect(info?[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == true)
    #expect(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
    controls.setNowPlaying(title: "ooooh", playing: false)
    let paused = MPNowPlayingInfoCenter.default().nowPlayingInfo
    #expect(paused?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)

    controls.unregister()
    controls.clearNowPlaying()
    #expect(commands.map(\.isEnabled) == [false, false, false, false])
    #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil)
  }
}
