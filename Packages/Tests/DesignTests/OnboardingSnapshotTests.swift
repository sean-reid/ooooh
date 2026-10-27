#if canImport(UIKit)
  import SnapshotTesting
  import SwiftUI
  import TestSupport
  import Testing
  import UIKit

  @testable import Design

  /// Reference PNGs live in __Snapshots__ and are rendered on the iPhone 17 Pro simulator.
  @MainActor
  @Suite struct OnboardingSnapshotTests {
    nonisolated static let looks: [(device: Device, scheme: ColorScheme)] = [
      (.small, .dark), (.small, .light), (.large, .dark), (.large, .light),
    ]

    @Test(arguments: OnboardingPage.allCases, looks)
    func page(page: OnboardingPage, look: (device: Device, scheme: ColorScheme)) {
      let image = render(
        screen(page), width: look.device.width, height: look.device.height, scheme: look.scheme)
      assertSnapshot(
        of: image, as: .pixels, named: "\(page.rawValue)-\(look.device.name)-\(look.scheme.name)")
    }

    @Test(arguments: OnboardingPage.allCases, [ColorScheme.dark, .light])
    func pageAccessibility3(page: OnboardingPage, scheme: ColorScheme) {
      let image = render(screen(page), scheme: scheme, type: .accessibility3)
      assertSnapshot(
        of: image, as: .pixels, named: "\(page.rawValue)-402-accessibility3-\(scheme.name)")
    }

    @Test(arguments: CaptureDenial.allCases, looks)
    func recovery(denial: CaptureDenial, look: (device: Device, scheme: ColorScheme)) {
      let image = render(
        recoveryScreen(denial), width: look.device.width, height: look.device.height,
        scheme: look.scheme)
      assertSnapshot(
        of: image, as: .pixels,
        named: "\(denial.rawValue)-\(look.device.name)-\(look.scheme.name)")
    }

    @Test(arguments: CaptureDenial.allCases, [ColorScheme.dark, .light])
    func recoveryAccessibility3(denial: CaptureDenial, scheme: ColorScheme) {
      let image = render(recoveryScreen(denial), scheme: scheme, type: .accessibility3)
      assertSnapshot(
        of: image, as: .pixels, named: "\(denial.rawValue)-402-accessibility3-\(scheme.name)")
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
