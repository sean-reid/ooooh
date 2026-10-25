#if canImport(UIKit)
  import SnapshotTesting
  import SwiftUI
  import Testing
  import UIKit

  @testable import Design

  /// Reference PNGs live in __Snapshots__ and are rendered on the iPhone 17 Pro simulator.
  @MainActor
  @Suite struct OnboardingSnapshotTests {
    nonisolated static let looks:
      [(name: String, width: CGFloat, height: CGFloat, scheme: ColorScheme)] = [
        ("375", 375, 667, .dark), ("375", 375, 667, .light),
        ("440", 440, 956, .dark), ("440", 440, 956, .light),
      ]

    @Test(arguments: OnboardingPage.allCases, looks)
    func page(
      page: OnboardingPage,
      look: (name: String, width: CGFloat, height: CGFloat, scheme: ColorScheme)
    ) {
      let image = render(
        screen(page), width: look.width, height: look.height, scheme: look.scheme)
      assertSnapshot(
        of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
        named: "\(page.rawValue)-\(look.name)-\(look.scheme.name)")
    }

    @Test(arguments: OnboardingPage.allCases, [ColorScheme.dark, .light])
    func pageAccessibility3(page: OnboardingPage, scheme: ColorScheme) {
      let image = render(
        screen(page), width: 402, height: 874, scheme: scheme, type: .accessibility3)
      assertSnapshot(
        of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
        named: "\(page.rawValue)-402-accessibility3-\(scheme.name)")
    }

    @Test(arguments: CaptureDenial.allCases, looks)
    func recovery(
      denial: CaptureDenial,
      look: (name: String, width: CGFloat, height: CGFloat, scheme: ColorScheme)
    ) {
      let image = render(
        recoveryScreen(denial), width: look.width, height: look.height, scheme: look.scheme)
      assertSnapshot(
        of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
        named: "\(denial.rawValue)-\(look.name)-\(look.scheme.name)")
    }

    @Test(arguments: CaptureDenial.allCases, [ColorScheme.dark, .light])
    func recoveryAccessibility3(denial: CaptureDenial, scheme: ColorScheme) {
      let image = render(
        recoveryScreen(denial), width: 402, height: 874, scheme: scheme, type: .accessibility3)
      assertSnapshot(
        of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
        named: "\(denial.rawValue)-402-accessibility3-\(scheme.name)")
    }

    private func screen(_ page: OnboardingPage) -> some View {
      var screen = OnboardingScreen(page: page, orbTime: 4.2, select: { _ in }, start: {})
      screen.scrolls = false
      return screen.background(Palette.sky)
    }

    private func recoveryScreen(_ denial: CaptureDenial) -> some View {
      var screen = PermissionRecoveryScreen(denial: denial, orbTime: 4.2) {}
      screen.scrolls = false
      return screen.background(Palette.sky)
    }
  }
#endif
