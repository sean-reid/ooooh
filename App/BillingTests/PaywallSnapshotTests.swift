import Foundation
import SnapshotTesting
import SwiftUI
import TestSupport
import Testing
import UIKit

@testable import Billing

/// Reference PNGs live in __Snapshots__ and are rendered on the iPhone 17 Pro simulator.
@MainActor
@Suite struct PaywallSnapshotTests {
  private final class Marker {}

  /// The subscriptions in Products.storekit, priced on the US storefront the way `Plan` prices a
  /// `Product`: the display price, and a twelfth of it a month for yearly.
  nonisolated static let plans: [Plan] = {
    struct Catalog: Decodable {
      struct Group: Decodable { var subscriptions: [Subscription] }
      struct Subscription: Decodable {
        var productID: String
        var displayPrice: String
      }
      var subscriptionGroups: [Group]
    }
    let catalog = try! Bundle(for: Marker.self).fixture("Products.storekit", as: Catalog.self)
    let dollars = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))
    let plans = catalog.subscriptionGroups.flatMap(\.subscriptions).compactMap { product in
      guard let id = ProductID(rawValue: product.productID),
        let price = Decimal(string: product.displayPrice)
      else { return nil as Plan? }
      return Plan(
        id: id, price: price.formatted(dollars),
        perMonth: id == .yearly ? (price / 12).formatted(dollars) : nil)
    }
    return ProductID.allCases.compactMap { id in plans.first { $0.id == id } }
  }()

  @Test func theConfigurationPricesBothPlans() {
    #expect(Self.plans.map(\.id) == [.monthly, .yearly])
    #expect(Self.plans.allSatisfy { $0.price.hasPrefix("$") })
    #expect(Self.plans.first { $0.id == .yearly }?.perMonth?.hasPrefix("$") == true)
    #expect(Self.plans.first { $0.id == .monthly }?.perMonth == nil)
  }

  @Test(arguments: [ColorScheme.dark, .light])
  func paywall(scheme: ColorScheme) {
    assertSnapshot(of: render(scheme: scheme), as: .pixels, named: "402-\(scheme.name)")
  }

  @Test(arguments: [ColorScheme.dark, .light])
  func paywallAccessibility3(scheme: ColorScheme) {
    assertSnapshot(
      of: render(scheme: scheme, type: .accessibility3), as: .pixels,
      named: "402-accessibility3-\(scheme.name)")
  }

  @Test(arguments: [ColorScheme.dark, .light])
  func paywallWithoutPlans(scheme: ColorScheme) {
    assertSnapshot(
      of: render(store: BillingStore(plans: []), scheme: scheme), as: .pixels,
      named: "402-\(scheme.name)")
  }

  @Test(arguments: [ColorScheme.dark, .light])
  func paywallLoading(scheme: ColorScheme) {
    assertSnapshot(
      of: render(store: BillingStore(plans: [], hasLoadedPlans: false), scheme: scheme),
      as: .pixels, named: "402-\(scheme.name)")
  }

  @Test(arguments: [ColorScheme.dark, .light])
  func paywallUnconfirmed(scheme: ColorScheme) {
    let store = BillingStore(plans: Self.plans, confirmation: .refused(reason: "wrong-device"))
    assertSnapshot(
      of: render(store: store, scheme: scheme), as: .pixels, named: "402-\(scheme.name)")
  }

  private func render(
    store: BillingStore? = nil, scheme: ColorScheme, type: DynamicTypeSize = .large
  ) -> UIImage {
    var view = PaywallView(store: store ?? BillingStore(plans: Self.plans)) {}
    view.scrolls = false
    return TestSupport.render(view, scheme: scheme, type: type)
  }
}
