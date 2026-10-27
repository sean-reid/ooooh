import MediaPlayer

/// A button on headphones, a car, or the lock screen that reaches the now-playing app.
enum MediaCommand: CaseIterable, Sendable {
  case play, pause, togglePlayPause, stop
}

/// The system's media controls as the controller touches them, so tests can hand in a fake.
@MainActor protocol MediaControls: AnyObject, Sendable {
  /// Routes each of `commands` to `handler` until `unregister()`.
  func register(_ commands: [MediaCommand], handler: @escaping @MainActor (MediaCommand) -> Void)
  func unregister()
  /// Commands only arrive while something is published as now playing.
  func setNowPlaying(title: String)
  func clearNowPlaying()
}

/// `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter`.
@MainActor final class SystemMediaControls: MediaControls {
  private var targets: [(MPRemoteCommand, Any)] = []

  func register(_ commands: [MediaCommand], handler: @escaping @MainActor (MediaCommand) -> Void) {
    unregister()
    for command in commands {
      let remote = Self.remote(command)
      remote.isEnabled = true
      let target = remote.addTarget { _ in
        Task { @MainActor in handler(command) }
        return .success
      }
      targets.append((remote, target))
    }
  }

  func unregister() {
    for (remote, target) in targets {
      remote.removeTarget(target)
      remote.isEnabled = false
    }
    targets = []
  }

  func setNowPlaying(title: String) {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: title,
      MPNowPlayingInfoPropertyIsLiveStream: true,
      MPNowPlayingInfoPropertyPlaybackRate: 1.0,
    ]
  }

  func clearNowPlaying() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  private static func remote(_ command: MediaCommand) -> MPRemoteCommand {
    let center = MPRemoteCommandCenter.shared()
    return switch command {
    case .play: center.playCommand
    case .pause: center.pauseCommand
    case .togglePlayPause: center.togglePlayPauseCommand
    case .stop: center.stopCommand
    }
  }
}
