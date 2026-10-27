import CloudKit
import Foundation
import Observation
import Persistence
import Settings

/// The one store the app opens, with the configuration it runs on. `current` is nil when neither
/// the CloudKit nor the local database opens, and that run keeps no history.
@MainActor @Observable
final class AppStore {
  static let shared = AppStore()
  /// What the last CloudKit account check found, read at launch before the next check answers.
  nonisolated static let accountKey = "cloud.accountAvailable"

  private(set) var current: SessionStore?
  private(set) var configuration: StoreConfiguration?
  /// Set while a reopen is in flight, so Settings shows the choice and not the store it replaces.
  private(set) var pending: StoreConfiguration?
  private(set) var accountAvailable: Bool
  /// The configuration last asked for; `configuration` differs after a fallback.
  @ObservationIgnored private var asked: StoreConfiguration
  @ObservationIgnored private let settings = AppSettings()
  @ObservationIgnored private var watching = false

  /// The launch choice, from the switch and the account state the last launch recorded, so the
  /// first frame waits on no CloudKit call.
  nonisolated static let launchSelection: StoreConfiguration = {
    let defaults = UserDefaults.standard
    return StoreSelection.configuration(
      accountAvailable: defaults.bool(forKey: accountKey),
      syncEnabled: AppSettings.cloudSyncEnabled(in: defaults))
  }()

  /// Opened on a background thread from the app's init.
  nonisolated static let opened: SessionStore.Opened? = LaunchTiming.measure("store") {
    try? FileManager.default.createDirectory(
      at: .applicationSupportDirectory, withIntermediateDirectories: true)
    return try? SessionStore.open(launchSelection)
  }

  private init() {
    current = Self.opened?.store
    configuration = Self.opened?.configuration
    asked = Self.launchSelection
    accountAvailable = UserDefaults.standard.bool(forKey: Self.accountKey)
  }

  /// The configuration Settings describes: the one being opened, else the one in use.
  var running: StoreConfiguration? { pending ?? configuration }

  /// Asks CloudKit for the account now and after every account change, reopening the store when
  /// the answer changes the choice.
  func watchAccount() async {
    guard !watching else { return }
    watching = true
    await refreshAccount()
    for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
      await refreshAccount()
    }
  }

  func refreshAccount() async {
    let container = CKContainer(identifier: PersistenceContainer.cloudContainerIdentifier)
    let status = try? await container.accountStatus()
    accountAvailable = status == .available
    UserDefaults.standard.set(accountAvailable, forKey: Self.accountKey)
    await apply()
  }

  /// Reopens the store when the account or the switch has changed the choice. A session already
  /// running keeps the store it started with; both write the same file.
  func apply() async {
    guard current != nil else { return }
    let wanted = StoreSelection.configuration(
      accountAvailable: accountAvailable, syncEnabled: settings.cloudSyncEnabled)
    guard wanted != asked else { return }
    asked = wanted
    pending = wanted
    let opened = await Task.detached(priority: .userInitiated) {
      try? SessionStore.open(wanted)
    }.value
    guard asked == wanted else { return }
    pending = nil
    guard let opened else { return }
    current = opened.store
    configuration = opened.configuration
  }
}
