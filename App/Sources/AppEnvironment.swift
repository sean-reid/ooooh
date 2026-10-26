import Billing
import Persistence
import Proxy
import UIKit

extension SessionController.Environment {
  /// The device's Worker, voice, haptic, and store. Debug builds take `-force-voice 1` to speak on
  /// the phone speaker and `-free-exhausted 1` to run every session as one the Worker refused.
  static var app: Self {
    var environment = Self(workerURL: WorkerURL.fromBundle)
    environment.haptic = { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    environment.store = AppStore.shared
    environment.attestor = AppAttestor.shared
    #if DEBUG
      environment.forceVoice = UserDefaults.standard.bool(forKey: "force-voice")
      if UserDefaults.standard.bool(forKey: "free-exhausted") { environment.gate = .exhausted }
    #endif
    return environment
  }
}

/// The one attestor the app signs Worker requests with; its key id also fixes the token a
/// purchase carries. Nil without a Worker URL, when a purchase keeps the stored random token.
enum AppAttestor {
  static let shared: (any Attestor)? = WorkerURL.fromBundle.map {
    ProxyClient.attestor(baseURL: $0)
  }
}

/// The one billing store the app opens, reading the free count from the sessions it runs.
@MainActor enum AppBilling {
  static let freeSessions = FreeSessions()
  static let store = BillingStore(
    freeSessions: freeSessions, attestor: AppAttestor.shared, poster: poster)

  /// Posts each transaction to the Worker, signed. The simulator cannot attest, so it posts none.
  static let poster: EntitlementPoster? = {
    guard let url = WorkerURL.fromBundle, let attestor = AppAttestor.shared,
      !(attestor is SimulatorAttestor)
    else { return nil }
    return .worker(ProxyClient(baseURL: url, attestor: attestor))
  }()
}

/// The one store the app opens. Nil when the local database cannot be opened, and that run keeps no history.
enum AppStore {
  static let shared: SessionStore? = {
    try? FileManager.default.createDirectory(
      at: .applicationSupportDirectory, withIntermediateDirectories: true)
    return try? SessionStore(configuration: .local)
  }()
}
