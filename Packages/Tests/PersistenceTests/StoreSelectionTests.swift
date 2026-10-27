import Foundation
import SwiftData
import Testing

@testable import Persistence

@Suite struct StoreSelectionTests {
  @Test func cloudOnlyWithAnAccountAndTheSwitchOn() {
    #expect(StoreSelection.configuration(accountAvailable: true, syncEnabled: true) == .cloud)
    #expect(StoreSelection.configuration(accountAvailable: true, syncEnabled: false) == .local)
    #expect(StoreSelection.configuration(accountAvailable: false, syncEnabled: true) == .local)
    #expect(StoreSelection.configuration(accountAvailable: false, syncEnabled: false) == .local)
  }

  /// The cloud attempt opens a database at a path that is a directory, which SQLite refuses.
  @Test func aCloudStoreThatDoesNotOpenFallsBackToLocal() async throws {
    var attempts: [StoreConfiguration] = []
    let opened = try SessionStore.open(.cloud) { configuration in
      attempts.append(configuration)
      return try configuration == .cloud ? Self.unopenable() : PersistenceContainer.make(.inMemory)
    }
    #expect(attempts == [.cloud, .local])
    #expect(opened.configuration == .local)
    #expect(try await opened.store.sessionCount() == 0)
  }

  @Test func aLocalStoreThatDoesNotOpenThrows() {
    var attempts: [StoreConfiguration] = []
    #expect(throws: (any Error).self) {
      try SessionStore.open(.local) { configuration in
        attempts.append(configuration)
        return try Self.unopenable()
      }
    }
    #expect(attempts == [.local])
  }

  @Test func theDefaultOpenerUsesThePersistenceContainer() async throws {
    let opened = try SessionStore.open(.inMemory)
    #expect(opened.configuration == .inMemory)
    #expect(try await opened.store.sessionCount() == 0)
  }

  static func unopenable() throws -> ModelContainer {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ooooh-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let configuration = ModelConfiguration(
      schema: PersistenceContainer.schema, url: url, cloudKitDatabase: .none)
    return try ModelContainer(for: PersistenceContainer.schema, configurations: [configuration])
  }
}
