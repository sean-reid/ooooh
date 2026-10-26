import Proxy
import XCTest

@testable import Billing

/// Needs no StoreKit session, so it runs on every runtime.
@MainActor
final class BillingLogicTests: XCTestCase {
  func testPriceLinesReadAsSpoken() {
    XCTAssertEqual(Plan(id: .monthly, price: "$6.99").priceLine, "$6.99 a month")
    XCTAssertEqual(
      Plan(id: .yearly, price: "$49.99", perMonth: "$4.17").priceLine,
      "$49.99 a year, $4.17 a month")
  }

  func testFreeSessionCountComesFromOutside() {
    let store = BillingStore(plans: [])
    XCTAssertEqual(store.entitlement, .free(remainingSessions: 3))
    store.freeSessionsRemaining = 1
    XCTAssertEqual(store.entitlement, .free(remainingSessions: 1))
  }

  func testLoadMarksThePlansLoadedWhateverStoreKitReturns() async {
    let store = BillingStore()
    XCTAssertFalse(store.hasLoadedPlans)
    try? await store.load()
    XCTAssertTrue(store.hasLoadedPlans)
  }

  func testFixedPlansCountAsLoaded() {
    XCTAssertTrue(BillingStore(plans: []).hasLoadedPlans)
    XCTAssertFalse(BillingStore(plans: [], hasLoadedPlans: false).hasLoadedPlans)
  }

  func testRefreshReadsTheFreeCountFromItsSource() async {
    let source = CountedSessions(remaining: 0)
    let store = BillingStore(freeSessions: source)
    XCTAssertEqual(store.entitlement, .free(remainingSessions: 3))
    await store.refresh()
    XCTAssertEqual(store.entitlement, .free(remainingSessions: 0))
    XCTAssertEqual(store.freeSessionsRemaining, 0)
  }

  func testRefreshKeepsTheCountWhenTheSourceHasNoAnswerYet() async {
    let store = BillingStore(freeSessions: CountedSessions(remaining: nil))
    await store.refresh()
    XCTAssertEqual(store.entitlement, .free(remainingSessions: 3))
  }

  struct CountedSessions: FreeSessionCount {
    var remaining: Int?
    var remainingFreeSessions: Int? { remaining }
  }

  func testOnlyARefusalLeavesTheStoreUnconfirmed() {
    XCTAssertFalse(BillingStore(plans: []).isUnconfirmed)
    let confirmed = BillingStore(
      plans: [], confirmation: .confirmed(EntitlementResponse(entitlement: .paid)))
    XCTAssertFalse(confirmed.isUnconfirmed)
    XCTAssertTrue(BillingStore(plans: [], confirmation: .refused(reason: "stale")).isUnconfirmed)
  }

  func testOnlySubscribedAndGraceArePaid() {
    XCTAssertTrue(Entitlement.subscribed(expires: .distantFuture, product: .monthly).isPaid)
    XCTAssertTrue(Entitlement.inGrace.isPaid)
    XCTAssertFalse(Entitlement.revoked.isPaid)
    XCTAssertFalse(Entitlement.free(remainingSessions: 3).isPaid)
  }

  func testProductIDsAndGroup() {
    XCTAssertEqual(ProductID.monthly.rawValue, "com.seanreid.ooooh.monthly")
    XCTAssertEqual(ProductID.yearly.rawValue, "com.seanreid.ooooh.yearly")
    XCTAssertEqual(ProductID.subscriptionGroup, "ooooh.listener")
  }
}
