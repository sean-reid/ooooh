import Foundation
import Testing

@testable import Settings

@MainActor
@Suite struct AppSettingsTests {
  let suite = "settings-tests-\(UUID().uuidString)"

  func freshDefaults() throws -> UserDefaults {
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }

  @Test func defaultsAreChallengeOnAutomaticAndSyncOn() throws {
    let defaults = try freshDefaults()
    let settings = AppSettings(defaults: defaults)
    #expect(settings.challengeEnabled)
    #expect(settings.quietModeOverride == .auto)
    #expect(settings.cloudSyncEnabled)
    #expect(AppSettings.cloudSyncEnabled(in: defaults))
  }

  @Test func valuesRoundTripThroughANewInstanceOnTheSameDefaults() throws {
    let defaults = try freshDefaults()
    let settings = AppSettings(defaults: defaults)
    settings.challengeEnabled = false
    settings.quietModeOverride = .quiet
    settings.cloudSyncEnabled = false

    let reread = AppSettings(defaults: defaults)
    #expect(!reread.challengeEnabled)
    #expect(reread.quietModeOverride == .quiet)
    #expect(!reread.cloudSyncEnabled)
    #expect(!AppSettings.cloudSyncEnabled(in: defaults))
    #expect(defaults.string(forKey: "settings.quietModeOverride") == "quiet")
    #expect(defaults.object(forKey: "settings.challengeEnabled") as? Bool == false)
    #expect(defaults.object(forKey: "settings.cloudSyncEnabled") as? Bool == false)
  }

  @Test func anUnknownStoredOverrideFallsBackToAutomatic() throws {
    let defaults = try freshDefaults()
    defaults.set("whisper", forKey: "settings.quietModeOverride")
    #expect(AppSettings(defaults: defaults).quietModeOverride == .auto)
  }

  @Test func changesNotifyObservers() async throws {
    let settings = AppSettings(defaults: try freshDefaults())
    await confirmation { changed in
      withObservationTracking {
        _ = settings.challengeEnabled
      } onChange: {
        changed()
      }
      settings.challengeEnabled = false
    }
  }
}
