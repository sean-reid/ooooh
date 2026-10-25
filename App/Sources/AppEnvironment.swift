import Persistence
import UIKit

extension SessionController.Environment {
  /// The device's Worker, voice, haptic, and store. Debug builds take `-force-voice 1` to speak on the phone speaker.
  static var app: Self {
    var environment = Self(workerURL: WorkerURL.fromBundle)
    environment.haptic = { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    environment.store = AppStore.shared
    #if DEBUG
      environment.forceVoice = UserDefaults.standard.bool(forKey: "force-voice")
    #endif
    return environment
  }
}

/// The one store the app opens. Nil when the local database cannot be opened, and that run keeps no history.
enum AppStore {
  static let shared: SessionStore? = {
    try? FileManager.default.createDirectory(
      at: .applicationSupportDirectory, withIntermediateDirectories: true)
    return try? SessionStore(configuration: .local)
  }()
}
