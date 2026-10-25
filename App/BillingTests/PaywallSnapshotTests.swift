import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import Billing

/// Reference PNGs live in __Snapshots__ and are rendered on the iPhone 17 Pro simulator.
@MainActor
@Suite struct PaywallSnapshotTests {
  /// The prices Products.storekit yields on the US storefront; BillingStoreTests checks them.
  nonisolated static let plans = [
    Plan(id: .monthly, price: "$6.99"), Plan(id: .yearly, price: "$49.99", perMonth: "$4.17"),
  ]

  @Test(arguments: [ColorScheme.dark, .light])
  func paywall(scheme: ColorScheme) {
    let image = render(scheme: scheme)
    assertSnapshot(
      of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
      named: "402-\(scheme.name)")
  }

  @Test(arguments: [ColorScheme.dark, .light])
  func paywallAccessibility3(scheme: ColorScheme) {
    let image = render(scheme: scheme, type: .accessibility3)
    assertSnapshot(
      of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
      named: "402-accessibility3-\(scheme.name)")
  }

  private func render(
    scheme: ColorScheme, width: CGFloat = 402, height: CGFloat = 874,
    type: DynamicTypeSize = .large
  ) -> UIImage {
    var view = PaywallView(store: BillingStore(plans: Self.plans)) {}
    view.scrolls = false
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
