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

  @Test func defaultsAreChallengeOnKeepAudioOffAndAutomatic() throws {
    let settings = AppSettings(defaults: try freshDefaults())
    #expect(settings.challengeEnabled)
    #expect(!settings.keepAudioByDefault)
    #expect(settings.quietModeOverride == .auto)
  }

  @Test func valuesRoundTripThroughANewInstanceOnTheSameDefaults() throws {
    let defaults = try freshDefaults()
    let settings = AppSettings(defaults: defaults)
    settings.challengeEnabled = false
    settings.keepAudioByDefault = true
    settings.quietModeOverride = .quiet

    let reread = AppSettings(defaults: defaults)
    #expect(!reread.challengeEnabled)
    #expect(reread.keepAudioByDefault)
    #expect(reread.quietModeOverride == .quiet)
    #expect(defaults.string(forKey: "settings.quietModeOverride") == "quiet")
    #expect(defaults.object(forKey: "settings.challengeEnabled") as? Bool == false)
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
        _ = settings.keepAudioByDefault
      } onChange: {
        changed()
      }
      settings.keepAudioByDefault = true
    }
  }
}
