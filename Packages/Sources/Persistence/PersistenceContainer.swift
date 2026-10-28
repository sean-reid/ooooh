import Foundation
import SwiftData

/// Where the store lives. The app passes `.cloud` only once the iCloud
/// entitlement exists; `.local` runs without it and `.inMemory` is for tests.
public enum StoreConfiguration: Sendable, Equatable {
  case inMemory
  case local
  case cloud
}

public enum PersistenceContainer {
  public static let cloudContainerIdentifier = "iCloud.com.seanreid.ooooh"

  public static let schema = Schema([
    StoredSession.self, StoredSegment.self, StoredLine.self, StoredNoteItem.self,
    StoredThread.self,
  ])

  public static func make(_ configuration: StoreConfiguration) throws -> ModelContainer {
    let modelConfiguration =
      switch configuration {
      case .inMemory:
        // Each in-memory store gets its own name; two sharing the default name fail to save.
        ModelConfiguration(
          UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      case .local:
        ModelConfiguration(schema: schema, cloudKitDatabase: .none)
      case .cloud:
        ModelConfiguration(
          schema: schema, cloudKitDatabase: .private(cloudContainerIdentifier))
      }
    return try make(modelConfiguration)
  }

  static func make(_ configuration: ModelConfiguration) throws -> ModelContainer {
    let container = try ModelContainer(for: schema, configurations: [configuration])
    try backfillThreadDates(in: container)
    return container
  }

  /// A thread still at the column default takes its session's start, so the sort key holds for every row.
  static func backfillThreadDates(in container: ModelContainer) throws {
    let context = ModelContext(container)
    let unset = Date.distantPast
    let descriptor = FetchDescriptor<StoredThread>(
      predicate: #Predicate { $0.sessionStartedAt == unset && $0.sourceSession != nil })
    let threads = try context.fetch(descriptor)
    guard !threads.isEmpty else { return }
    for thread in threads {
      if let session = thread.sourceSession {
        thread.sessionStartedAt = session.startedAt
      }
    }
    try context.save()
  }
}
