import Persistence

/// What the iCloud row in Settings says, from the store the app runs on and what was asked of it.
public enum CloudSyncState: Equatable, Sendable {
  case syncing
  case off
  case noAccount
  /// The switch is on and the phone has an account, and the CloudKit store still did not open.
  case failed

  public init(configuration: StoreConfiguration?, accountAvailable: Bool, syncEnabled: Bool) {
    self =
      if configuration == .cloud {
        .syncing
      } else if !syncEnabled {
        .off
      } else if !accountAvailable {
        .noAccount
      } else {
        .failed
      }
  }

  public var line: String {
    switch self {
    case .syncing: "Syncing with iCloud"
    case .off: "Off. Sessions stay on this phone."
    case .noAccount: "Not signed in to iCloud"
    case .failed: "iCloud could not be opened. Sessions stay on this phone."
    }
  }
}
