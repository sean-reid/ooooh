#if os(iOS)
  import AVFAudio
  import Foundation
  import OSLog

  /// Owns the shared audio session. Voice chat mode keeps hardware echo cancellation on, so the app can speak while the mic stays open.
  public struct AudioSessionController: Sendable {
    private static let log = Logger(subsystem: "com.seanreid.ooooh", category: "audio")

    public init() {}

    public func activate() throws {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord, mode: .voiceChat,
        options: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker])
      try session.setActive(true)
      let route = session.currentRoute
      Self.log.info(
        """
        session active category=\(session.category.rawValue, privacy: .public) \
        mode=\(session.mode.rawValue, privacy: .public) \
        input=\(Self.describe(route.inputs), privacy: .public) \
        output=\(Self.describe(route.outputs), privacy: .public) \
        sampleRate=\(Int(session.sampleRate), privacy: .public)
        """)
    }

    /// "MicrophoneBuiltIn(iPhone Microphone)", one per port.
    private static func describe(_ ports: [AVAudioSessionPortDescription]) -> String {
      ports.isEmpty
        ? "none" : ports.map { "\($0.portType.rawValue)(\($0.portName))" }.joined(separator: ",")
    }

    public func deactivate() throws {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    public var currentRoute: AudioRoute {
      AudioRoute(
        outputPortTypes: AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType),
        inputPortTypes: AVAudioSession.sharedInstance().currentRoute.inputs.map(\.portType))
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
    /// Headphones only when the microphone travels with the output: a Bluetooth speaker plays
    /// over A2DP while the phone's own microphone keeps listening, so it counts as other.
    public init(
      outputPortTypes ports: [AVAudioSession.Port],
      inputPortTypes inputs: [AVAudioSession.Port] = []
    ) {
      let route = ports.lazy.compactMap(AudioRoute.init(port:)).first ?? .other
      let micOnThePhone = inputs.contains(.builtInMic)
      let wirelessOutput = ports.contains { $0 == .bluetoothA2DP || $0 == .bluetoothLE }
      self = route == .headphones && wirelessOutput && micOnThePhone ? .other : route
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
