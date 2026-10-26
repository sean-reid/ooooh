#if os(iOS) && canImport(StoreKitTest)
  import Proxy
  import StoreKit
  import StoreKitTest
  import Synchronization
  import XCTest

  @testable import Billing
  @testable import ooooh

  /// Answers one fixed key id and counts how often it is asked for it.
  final class FakeAttestor: Attestor {
    let key: String
    private let requests = Mutex(0)

    var keyIdRequests: Int { requests.withLock { $0 } }

    init(key: String) {
      self.key = key
    }

    func assertion(clientDataHash: Data) async throws -> Assertion? {
      Assertion(keyId: key, assertion: Data())
    }

    func keyId() async throws -> String? {
      requests.withLock { $0 += 1 }
      return key
    }
  }

  /// A store built as AppBilling builds it, with the attestor replaced, buying from
  /// App/Resources/Products.storekit.
  @MainActor
  final class PurchaseTokenTests: XCTestCase {
    func testAppAttestorOnTheSimulatorSignsNothing() async throws {
      let attestor = try XCTUnwrap(AppAttestor.shared)
      XCTAssertTrue(attestor is SimulatorAttestor)
      let keyId = try await attestor.keyId()
      XCTAssertNil(keyId)
    }

    func testPurchaseAsksTheAttestorForTheKeyIdAndStampsTheDerivedToken() async throws {
      let session = try TestSession.make()
      defer { session.clearTransactions() }
      let attestor = FakeAttestor(key: "key-1")
      let store = BillingStore(freeSessions: AppBilling.freeSessions, attestor: attestor)
      try await store.load()

      do {
        try await store.purchase(.monthly)
      } catch BillingError.productUnavailable {
        XCTAssertTrue(store.plans.isEmpty, "the product loaded and was still unavailable")
      }
      XCTAssertEqual(attestor.keyIdRequests, 1)

      if store.plans.isEmpty {
        throw XCTSkip(
          "StoreKit returned no products for the test session, so the token on the transaction goes unchecked here. The iOS 26.4 simulator runtime refuses SKTestSession, Apple's FB22774836."
        )
      }
      let latest = await Transaction.latest(for: ProductID.monthly.rawValue)
      let transaction = try XCTUnwrap(latest).payloadValue
      XCTAssertEqual(transaction.appAccountToken, AppAccountToken.derive(keyId: "key-1"))
    }
  }
#endif
