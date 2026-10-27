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
  var nowPlaying: [String?] = []
  var unregistrations = 0

  func register(_ commands: [MediaCommand], handler: @escaping @MainActor (MediaCommand) -> Void) {
    registered = commands
    self.handler = handler
  }

  func unregister() {
    unregistrations += 1
    handler = nil
  }

  func setNowPlaying(title: String) { nowPlaying.append(title) }

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
    #expect(media.unregistrations == 0)

    await controller.end()
    #expect(controller.stage == .ended)
    #expect(media.unregistrations == 1)
    #expect(media.nowPlaying == ["ooooh", nil])
  }

  @Test(arguments: MediaCommand.allCases)
  func aCommandEndsTheSession(_ command: MediaCommand) async throws {
    let media = RecordingMediaControls()
    let controller = controller(media)
    await controller.start(.microphone)
    let handler = try #require(media.handler)

    handler(command)
    await wait { controller.stage == .ended }

    #expect(controller.stage == .ended)
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
    controls.setNowPlaying(title: "ooooh")
    #expect(commands.map(\.isEnabled) == [true, true, true, true])
    let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
    #expect(info?[MPMediaItemPropertyTitle] as? String == "ooooh")
    #expect(info?[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == true)

    controls.unregister()
    controls.clearNowPlaying()
    #expect(commands.map(\.isEnabled) == [false, false, false, false])
    #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil)
  }
}
