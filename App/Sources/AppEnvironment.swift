import UIKit

extension SessionController.Environment {
  /// The device's Worker, voice, and haptic. Debug builds take `-force-voice 1` to speak on the phone speaker.
  static var app: Self {
    var environment = Self(workerURL: WorkerURL.fromBundle)
    environment.haptic = { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    #if DEBUG
      environment.forceVoice = UserDefaults.standard.bool(forKey: "force-voice")
    #endif
    return environment
  }
}
