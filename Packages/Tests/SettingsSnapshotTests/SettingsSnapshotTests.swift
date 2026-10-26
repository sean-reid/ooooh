#if canImport(UIKit)
  import Persistence
  import SnapshotTesting
  import SwiftUI
  import Testing
  import UIKit

  @testable import Settings

  /// Reference PNGs live in __Snapshots__ and are rendered on the iPhone 17 Pro simulator.
  /// Images are 402 wide and as tall as the content, so every row is in the picture.
  @MainActor
  @Suite struct SettingsSnapshotTests {
    @Test(arguments: [ColorScheme.dark, .light])
    func settings(scheme: ColorScheme) throws {
      let image = render(try settingsView(), scheme: scheme)
      assertSnapshot(
        of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
        named: "402-\(scheme.name)")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func settingsWithChallengeOff(scheme: ColorScheme) throws {
      let image = render(try settingsView(challengeEnabled: false), scheme: scheme)
      assertSnapshot(
        of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
        named: "402-challenge-off-\(scheme.name)")
    }

    @Test func settingsAccessibility3() throws {
      let image = render(try settingsView(), scheme: .dark, type: .accessibility3)
      assertSnapshot(
        of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
        named: "402-accessibility3-dark")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func privacy(scheme: ColorScheme) {
      let image = render(privacyView(), scheme: scheme)
      assertSnapshot(
        of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
        named: "402-\(scheme.name)")
    }

    /// At accessibility3 the page is taller than ImageRenderer will draw, so this one renders
    /// the device height and shows the top.
    @Test func privacyAccessibility3() {
      let image = render(privacyView(), height: 874, scheme: .dark, type: .accessibility3)
      assertSnapshot(
        of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
        named: "402-accessibility3-dark")
    }

    private func settingsView(challengeEnabled: Bool = true) throws -> SettingsView {
      let suite = "settings-snapshots"
      let defaults = try #require(UserDefaults(suiteName: suite))
      defaults.removePersistentDomain(forName: suite)
      let settings = AppSettings(defaults: defaults)
      settings.challengeEnabled = challengeEnabled
      return SettingsView(
        settings: settings,
        store: try SessionStore(configuration: .inMemory), version: "0.1.0 (1)",
        sessionCount: 12, subscribeAction: {}, openHistory: {}, onDone: {})
    }

    private func privacyView() -> PrivacyView {
      var view = PrivacyView()
      view.scrolls = false
      return view
    }

    private func render(
      _ view: some View, width: CGFloat = 402, height: CGFloat? = nil, scheme: ColorScheme,
      type: DynamicTypeSize = .large
    ) -> UIImage {
      let renderer = ImageRenderer(
        content: view.frame(width: width, height: height, alignment: .top).clipped()
          .environment(\.colorScheme, scheme).dynamicTypeSize(type))
      renderer.scale = 2
      renderer.proposedSize = ProposedViewSize(width: width, height: height)
      return renderer.uiImage ?? UIImage()
    }
  }

  extension ColorScheme {
    fileprivate var name: String { self == .dark ? "dark" : "light" }
  }
#endif
