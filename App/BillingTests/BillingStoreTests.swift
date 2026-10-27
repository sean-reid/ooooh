#if os(iOS) && canImport(StoreKitTest)
  import StoreKit
  import StoreKitTest
  import TestSupport
  import Testing
  import XCTest

  @testable import Billing

  /// Buys from App/Resources/Products.storekit through SKTestSession, so it runs on the simulator.
  @MainActor
  final class BillingStoreTests: XCTestCase {
    private var session: SKTestSession!
    private var store: BillingStore!

    override func setUp() async throws {
      if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
        throw XCTSkip(
          "SKTestSession hangs inside Product.products on the simulator, Apple's FB22774836.")
      }
      session = try TestSession.make()
      store = BillingStore()
      try await store.load()
      if store.plans.isEmpty {
        throw XCTSkip(
          "StoreKit returned no products for the test session. The iOS 26.4 simulator runtime refuses SKTestSession, Apple's FB22774836."
        )
      }
    }

    override func tearDown() {
      session?.clearTransactions()
      session = nil
      store = nil
    }

    func testLoadsBothProductsFromTheConfiguration() {
      XCTAssertEqual(store.plans.map(\.id), [.monthly, .yearly])
      XCTAssertEqual(store.plans.map(\.price), ["$6.99", "$49.99"])
      XCTAssertEqual(store.entitlement, .free(remainingSessions: 3))
      XCTAssertNil(store.latestTransactionJWS)
    }

    func testYearlyShowsThePerMonthPrice() throws {
      let yearly = try XCTUnwrap(store.plans.first { $0.id == .yearly })
      XCTAssertEqual(yearly.perMonth, "$4.17")
      XCTAssertEqual(yearly.priceLine, "$49.99 a year, $4.17 a month")
      let monthly = try XCTUnwrap(store.plans.first { $0.id == .monthly })
      XCTAssertNil(monthly.perMonth)
      XCTAssertEqual(monthly.priceLine, "$6.99 a month")
    }

    func testPurchasingMonthlySubscribes() async throws {
      let entitlement = try await store.purchase(.monthly)
      guard case .subscribed(let expires, let product) = entitlement else {
        return XCTFail("expected subscribed, got \(entitlement)")
      }
      XCTAssertEqual(product, .monthly)
      XCTAssertGreaterThan(try XCTUnwrap(expires), .now)
      XCTAssertTrue(store.entitlement.isPaid)
      XCTAssertEqual(store.latestTransactionJWS?.split(separator: ".").count, 3)
    }

    func testRefundRevokes() async throws {
      try await store.purchase(.monthly)
      let transaction = try XCTUnwrap(session.allTransactions().first)
      try session.refundTransaction(identifier: UInt(transaction.identifier))
      await store.refresh()
      XCTAssertEqual(store.entitlement, .revoked)
      XCTAssertFalse(store.entitlement.isPaid)
    }

    func testRestoreBringsTheEntitlementBackToAFreshStore() async throws {
      try await store.purchase(.yearly)
      let fresh = BillingStore()
      XCTAssertEqual(fresh.entitlement, .free(remainingSessions: 3))
      let restored = try await fresh.restore()
      guard case .subscribed(_, let product) = restored else {
        return XCTFail("expected subscribed, got \(restored)")
      }
      XCTAssertEqual(product, .yearly)
      XCTAssertNotNil(fresh.latestTransactionJWS)
    }

    func testUpdatesStreamSeesAPurchaseMadeOutsideTheStore() async throws {
      _ = try await session.buyProduct(identifier: ProductID.monthly.rawValue)
      await TestSupport.wait(for: "the store sees the purchase", seconds: 5) {
        store.entitlement.isPaid
      }
    }

    func testGracePeriodKeepsAccess() async throws {
      session.shouldEnterBillingRetryOnRenewal = true
      session.billingGracePeriodIsEnabled = true
      try await store.purchase(.monthly)
      try session.forceRenewalOfSubscription(productIdentifier: ProductID.monthly.rawValue)
      await store.refresh()
      XCTAssertEqual(store.entitlement, .inGrace)
      XCTAssertTrue(store.entitlement.isPaid)
    }
  }
#endif
