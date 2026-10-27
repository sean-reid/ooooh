import Foundation
import OSLog
import SwiftData

let persistenceLog = Logger(subsystem: "com.seanreid.ooooh", category: "persistence")

/// Which store the app opens: CloudKit mirrors only while the phone has an iCloud account and the
/// sync switch is on.
public enum StoreSelection {
  public static func configuration(accountAvailable: Bool, syncEnabled: Bool)
    -> StoreConfiguration
  {
    accountAvailable && syncEnabled ? .cloud : .local
  }
}

extension SessionStore {
  /// A store with the configuration it opened on, which is `.local` after a fallback.
  public struct Opened: Sendable {
    public let store: SessionStore
    public let configuration: StoreConfiguration
  }

  /// Opens `configuration`. When `.cloud` throws, the error is logged and the local database opens
  /// in its place, so a CloudKit problem never costs the history.
  public static func open(
    _ configuration: StoreConfiguration,
    make: (StoreConfiguration) throws -> ModelContainer = PersistenceContainer.make
  ) throws -> Opened {
    do {
      return Opened(
        store: SessionStore(modelContainer: try make(configuration)), configuration: configuration)
    } catch {
      guard configuration == .cloud else { throw error }
      persistenceLog.error(
        "The CloudKit store did not open, using the local one: \(String(describing: error), privacy: .public)"
      )
      return Opened(store: SessionStore(modelContainer: try make(.local)), configuration: .local)
    }
  }
}
