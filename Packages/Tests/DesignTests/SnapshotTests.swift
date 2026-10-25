#if canImport(UIKit)
  import SnapshotTesting
  import SwiftUI
  import Testing
  import UIKit

  @testable import Design

  /// Reference PNGs live in __Snapshots__ and are rendered on the iPhone 17 Pro simulator.
  @MainActor
  @Suite struct SnapshotTests {
    nonisolated static let widths: [(name: String, width: CGFloat, height: CGFloat)] = [
      ("375", 375, 667), ("402", 402, 874), ("440", 440, 956),
    ]

    nonisolated static let levels: [(level: Double, scheme: ColorScheme)] = [
      (0, .dark), (0.7, .dark), (0, .light), (0.7, .light),
    ]

    @Test(arguments: OrbPhase.allCases, levels)
    func orb(phase: OrbPhase, look: (level: Double, scheme: ColorScheme)) {
      let (level, scheme) = look
      let image = render(
        Orb(level: level, phase: phase, time: 4.2).padding(20).background(Palette.sky),
        width: 240, height: 240, scheme: scheme)
      assertSnapshot(
        of: image, as: .image(perceptualPrecision: 0.98),
        named: "\(phase.rawValue)-\(level)-\(scheme.name)")
    }

    @Test(arguments: widths, [ColorScheme.dark, .light])
    func sessionScreen(
      device: (name: String, width: CGFloat, height: CGFloat), scheme: ColorScheme
    ) {
      let image = render(
        SessionScreenSample(time: 4.2), width: device.width, height: device.height,
        scheme: scheme)
      assertSnapshot(
        of: image, as: .image(perceptualPrecision: 0.98), named: "\(device.name)-\(scheme.name)")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func sessionScreenAccessibility3(scheme: ColorScheme) {
      let image = render(
        SessionScreenSample(time: 4.2), width: 402, height: 874, scheme: scheme,
        type: .accessibility3)
      assertSnapshot(
        of: image, as: .image(perceptualPrecision: 0.98),
        named: "402-accessibility3-\(scheme.name)")
    }

    private func render(
      _ view: some View, width: CGFloat, height: CGFloat, scheme: ColorScheme,
      type: DynamicTypeSize = .large
    ) -> UIImage {
      let renderer = ImageRenderer(
        content: view.frame(width: width, height: height).environment(\.colorScheme, scheme)
          .dynamicTypeSize(type))
      renderer.scale = 2
      renderer.proposedSize = ProposedViewSize(width: width, height: height)
      return renderer.uiImage ?? UIImage()
    }
  }

  extension ColorScheme {
    fileprivate var name: String { self == .dark ? "dark" : "light" }
  }
#endif
