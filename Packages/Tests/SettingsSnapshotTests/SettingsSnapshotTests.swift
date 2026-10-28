#if canImport(UIKit)
  import Billing
  import Persistence
  import SnapshotTesting
  import SwiftUI
  import TestSupport
  import Testing
  import UIKit

  @testable import Settings

  /// Reference PNGs live in __Snapshots__ and are rendered on the iPhone 17 Pro simulator.
  /// Images are 402 wide and as tall as the content, so every row is in the picture.
  @MainActor
  @Suite struct SettingsSnapshotTests {
    @Test(arguments: [ColorScheme.dark, .light])
    func settings(scheme: ColorScheme) throws {
      let image = render(try settingsView(), height: nil, scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "402-\(scheme.name)")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func settingsWithChallengeOff(scheme: ColorScheme) throws {
      let image = render(try settingsView(challengeEnabled: false), height: nil, scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "402-challenge-off-\(scheme.name)")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func settingsWithSyncOff(scheme: ColorScheme) throws {
      let image = render(try settingsView(cloudSync: .off), height: nil, scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "402-sync-off-\(scheme.name)")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func settingsWithNoAccount(scheme: ColorScheme) throws {
      let image = render(try settingsView(cloudSync: .noAccount), height: nil, scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "402-no-account-\(scheme.name)")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func settingsWithSyncFailed(scheme: ColorScheme) throws {
      let image = render(try settingsView(cloudSync: .failed), height: nil, scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "402-sync-failed-\(scheme.name)")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func settingsSubscribedMonthly(scheme: ColorScheme) throws {
      let view = try settingsView(
        entitlement: .subscribed(expires: Self.day(2026, 11, 27), product: .monthly))
      let image = render(view, height: nil, scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "402-monthly-\(scheme.name)")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func settingsSubscribedYearly(scheme: ColorScheme) throws {
      let view = try settingsView(
        entitlement: .subscribed(expires: Self.day(2027, 10, 27), product: .yearly))
      let image = render(view, height: nil, scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "402-yearly-\(scheme.name)")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func settingsInGrace(scheme: ColorScheme) throws {
      let view = try settingsView(entitlement: .inGrace(product: .monthly))
      let image = render(view, height: nil, scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "402-grace-\(scheme.name)")
    }

    @Test func settingsAccessibility3() throws {
      let image = render(try settingsView(), height: nil, scheme: .dark, type: .accessibility3)
      assertSnapshot(of: image, as: .pixels, named: "402-accessibility3-dark")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func privacy(scheme: ColorScheme) {
      let image = render(privacyView(), height: nil, scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "402-\(scheme.name)")
    }

    /// At accessibility3 the page is taller than ImageRenderer will draw, so this one renders
    /// the device height and shows the top.
    @Test func privacyAccessibility3() {
      let image = render(privacyView(), scheme: .dark, type: .accessibility3, alignment: .top)
      assertSnapshot(of: image, as: .pixels, named: "402-accessibility3-dark")
    }

    /// Noon UTC, so the day is the same in every zone the suite runs in.
    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: "UTC")!
      return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// The switch draws the state's own setting: off for `.off`, on for the rest. Renewal dates
    /// are read against October 27, 2026.
    private func settingsView(
      challengeEnabled: Bool = true, cloudSync: CloudSyncState = .syncing,
      entitlement: Entitlement = .free(remainingSessions: 3)
    ) throws -> SettingsView {
      let suite = "settings-snapshots"
      let defaults = try #require(UserDefaults(suiteName: suite))
      defaults.removePersistentDomain(forName: suite)
      let settings = AppSettings(defaults: defaults)
      settings.challengeEnabled = challengeEnabled
      settings.cloudSyncEnabled = cloudSync != .off
      return SettingsView(
        settings: settings,
        store: try SessionStore(configuration: .inMemory), version: "0.1.0 (1)",
        transcription: "On-device transcription", cloudSync: cloudSync, entitlement: entitlement,
        now: Self.day(2026, 10, 27), sessionCount: 12, subscribeAction: {}, openHistory: {},
        onDone: {})
    }

    private func privacyView() -> PrivacyView {
      var view = PrivacyView()
      view.scrolls = false
      return view
    }
  }
#endif
