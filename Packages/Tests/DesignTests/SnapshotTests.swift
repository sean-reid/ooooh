#if canImport(UIKit)
  import SnapshotTesting
  import SwiftUI
  import TestSupport
  import Testing
  import UIKit

  @testable import Design

  /// Reference PNGs live in __Snapshots__ and are rendered on the iPhone 17 Pro simulator.
  @MainActor
  @Suite struct SnapshotTests {
    nonisolated static let levels: [(level: Double, scheme: ColorScheme)] = [
      (0, .dark), (0.7, .dark), (0, .light), (0.7, .light),
    ]

    @Test(arguments: OrbPhase.allCases, levels)
    func orb(phase: OrbPhase, look: (level: Double, scheme: ColorScheme)) {
      let (level, scheme) = look
      let image = render(
        Orb(level: level, phase: phase, time: 4.2).padding(20).background(Palette.sky),
        width: 240, height: 240, scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "\(phase.rawValue)-\(level)-\(scheme.name)")
    }

    @Test(arguments: Device.all, [ColorScheme.dark, .light])
    func sessionScreen(device: Device, scheme: ColorScheme) {
      let image = render(
        SessionScreenSample(time: 4.2), width: device.width, height: device.height,
        scheme: scheme)
      assertSnapshot(of: image, as: .pixels, named: "\(device.name)-\(scheme.name)")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func sessionScreenAccessibility3(scheme: ColorScheme) {
      let image = render(SessionScreenSample(time: 4.2), scheme: scheme, type: .accessibility3)
      assertSnapshot(of: image, as: .pixels, named: "402-accessibility3-\(scheme.name)")
    }
  }
#endif
