import Billing
import OSLog
import Persistence
import Proxy
import Settings
import SwiftUI
import UIKit

extension SessionController.Environment {
  /// The device's Worker, voice, haptic, and store. Debug builds take `-force-voice 1` to speak on
  /// the phone speaker, `-free-exhausted 1` to run every session as one the Worker refused, and
  /// `-forget-attest-key 1` to enrol as a new device.
  @MainActor static var app: Self {
    #if DEBUG
      if UserDefaults.standard.bool(forKey: "forget-attest-key") {
        DeviceAttestation.forgetStoredKey()
      }
    #endif
    return LaunchTiming.measure("environment") {
      var environment = Self(workerURL: WorkerURL.fromBundle)
      environment.haptic = { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
      environment.announce = { AccessibilityNotification.Announcement($0).post() }
      environment.store = AppStore.shared.current
      environment.attestor = environment.workerURL.map { _ in DeferredAttestor() }
      environment.settings = AppSettings()
      environment.freeSessions = AppBilling.freeSessions
      #if DEBUG
        environment.forceVoice = UserDefaults.standard.bool(forKey: "force-voice")
        if UserDefaults.standard.bool(forKey: "free-exhausted") { environment.gate = .exhausted }
      #endif
      return environment
    }
  }
}

/// The launch work the first frame does not wait on. The store opens on a background thread from
/// the app's init, so the root view finds it open or waits for what is left of the open. The root
/// view's task builds the attestor on a background thread, and the billing store on the main actor
/// once the attestor exists, since the store's poster reads it.
@MainActor
final class LaunchWork {
  static let shared = LaunchWork()
  private(set) var isDone = false
  private var started = false

  /// Opens the store while UIKit brings the scene up.
  nonisolated static func openStore() {
    Task.detached(priority: .userInitiated) { _ = AppStore.opened }
  }

  func run() {
    guard !started else { return }
    started = true
    Task { await AppStore.shared.watchAccount() }
    Task.detached(priority: .utility) {
      _ = AppAttestor.shared
      await MainActor.run {
        _ = AppBilling.store
        self.isDone = true
      }
    }
  }
}

/// Signs with `AppAttestor.shared`, built on the first request rather than in the first frame.
struct DeferredAttestor: Attestor {
  func assertion(clientDataHash: Data) async throws -> Assertion? {
    try await AppAttestor.shared?.assertion(clientDataHash: clientDataHash)
  }

  func keyId() async throws -> String? { try await AppAttestor.shared?.keyId() }
}

/// Times one piece of launch work and logs it, so the first frame's cost is read, not guessed.
enum LaunchTiming {
  private static let log = Logger(subsystem: "com.seanreid.ooooh", category: "launch")

  static func mark(_ name: String) { log.info("\(name, privacy: .public)") }

  static func measure<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
    let clock = ContinuousClock()
    let start = clock.now
    defer {
      let elapsed = start.duration(to: clock.now).components
      let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
      log.info(
        "\(name, privacy: .public) \(milliseconds, format: .fixed(precision: 1), privacy: .public) ms"
      )
    }
    return try work()
  }
}

/// The one attestor the app signs Worker requests with; its key id also fixes the token a
/// purchase carries. Nil without a Worker URL, when a purchase keeps the stored random token.
enum AppAttestor {
  static let shared: (any Attestor)? = LaunchTiming.measure("attestor") {
    WorkerURL.fromBundle.map { ProxyClient.attestor(baseURL: $0) }
  }
}

/// The one billing store the app opens, reading the free count from the sessions it runs.
@MainActor enum AppBilling {
  static let freeSessions = FreeSessions()
  static let store = LaunchTiming.measure("billing") {
    BillingStore(freeSessions: freeSessions, attestor: AppAttestor.shared, poster: poster)
  }

  /// Posts each transaction to the Worker, signed. The simulator cannot attest, so it posts none.
  static let poster: EntitlementPoster? = {
    guard let url = WorkerURL.fromBundle, let attestor = AppAttestor.shared,
      !(attestor is SimulatorAttestor)
    else { return nil }
    return .worker(ProxyClient(baseURL: url, attestor: attestor))
  }()
}
