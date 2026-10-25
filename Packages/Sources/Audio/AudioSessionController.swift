#if os(iOS)
  import AVFAudio
  import Foundation

  /// Owns the shared audio session. Voice chat mode keeps hardware echo cancellation on, so the app can speak while the mic stays open.
  public struct AudioSessionController: Sendable {
    public init() {}

    public func activate() throws {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord, mode: .voiceChat,
        options: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker])
      try session.setActive(true)
    }

    public func deactivate() throws {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    public var currentRoute: AudioRoute {
      AudioRoute(
        outputPortTypes: AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType))
    }

    public func routeChanges() -> AsyncStream<AudioRoute> {
      AsyncStream { continuation in
        let task = Task {
          let changes = NotificationCenter.default.notifications(
            named: AVAudioSession.routeChangeNotification)
          for await _ in changes {
            continuation.yield(currentRoute)
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    }
  }

  extension AudioRoute {
    public init(outputPortTypes ports: [AVAudioSession.Port]) {
      self = ports.lazy.compactMap(AudioRoute.init(port:)).first ?? .other
    }

    private init?(port: AVAudioSession.Port) {
      switch port {
      case .carAudio: self = .car
      case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: self = .headphones
      case .builtInSpeaker: self = .speaker
      default: return nil
      }
    }
  }
#endif
