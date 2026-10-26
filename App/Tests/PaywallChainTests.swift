import Billing
import Foundation
import Proxy
import Testing

@testable import ooooh

/// The chain RootView wires after End: the controller's admission into `FreeSessions`, the
/// billing store's refresh reading it, and the paywall decision. The Worker is `GateProtocol`
/// and StoreKit is the `Held` double, each test on its own host.
@MainActor
@Suite struct PaywallChainTests {
  let controllers = SessionControllerTests()
  let posts = EntitlementPostTests()

  /// A controller admitted by `body`, and a store reading the free count the way AppBilling does.
  func chain(_ host: String, answering body: Data, transactions: TransactionSource = .none)
    -> (SessionController, FreeSessions, BillingStore)
  {
    let freeSessions = FreeSessions()
    let billing = BillingStore(freeSessions: freeSessions, transactions: transactions)
    let controller = SessionController(
      environment: controllers.gated(
        host, answering: body, deps: controllers.deps(firing: .deepen, at: 14.0)))
    return (controller, freeSessions, billing)
  }

  func admission(of controller: SessionController) async throws -> SessionStart {
    await controller.start(.fixture(controllers.shortFixture, speed: .infinity))
    await wait { controller.stage == .ended }
    return try #require(controller.admission)
  }

  @Test func aRefusedStartEmptiesTheFreeCountAndOffersThePaywall() async throws {
    let (controller, freeSessions, billing) = chain(
      "paywall-refused", answering: try controllers.workerFixture("session-start-refused"))
    #expect(freeSessions.remaining == nil)
    #expect(billing.entitlement == .free(remainingSessions: 3))
    #expect(!RootView.offersPaywall(billing))

    let admission = try await admission(of: controller)
    #expect(admission == .refused(reason: "free-exhausted"))
    freeSessions.record(admission)
    #expect(freeSessions.remaining == 0)
    #expect(await freeSessions.remainingFreeSessions == 0)

    await billing.refresh()
    #expect(billing.freeSessionsRemaining == 0)
    #expect(billing.entitlement == .free(remainingSessions: 0))
    #expect(RootView.offersPaywall(billing))
  }

  @Test func theLastFreeSessionOffersThePaywallWhenItEnds() async throws {
    let body = Data(#"{"allowed":true,"free":true,"remainingFree":0,"promptMinutes":20}"#.utf8)
    let (controller, freeSessions, billing) = chain("paywall-last", answering: body)

    let admission = try await admission(of: controller)
    #expect(admission == .free(remaining: 0, promptMinutes: 20))
    freeSessions.record(admission)
    await billing.refresh()
    #expect(billing.entitlement == .free(remainingSessions: 0))
    #expect(RootView.offersPaywall(billing))
  }

  @Test func aFreeSessionWithSessionsLeftOffersNothing() async throws {
    let (controller, freeSessions, billing) = chain(
      "paywall-free", answering: try controllers.workerFixture("session-start-free"))

    let admission = try await admission(of: controller)
    #expect(admission == .free(remaining: 2, promptMinutes: 20))
    freeSessions.record(admission)
    await billing.refresh()
    #expect(billing.entitlement == .free(remainingSessions: 2))
    #expect(!RootView.offersPaywall(billing))
  }

  @Test func aPaidSessionLeavesTheCountAloneAndOffersNothing() async throws {
    let held = EntitlementPostTests.Held(posts.monthly)
    let (controller, freeSessions, billing) = chain(
      "paywall-paid", answering: try controllers.workerFixture("session-start-paid"),
      transactions: held.source)

    let admission = try await admission(of: controller)
    #expect(admission == .paid)
    freeSessions.record(admission)
    #expect(freeSessions.remaining == nil)
    await billing.refresh()
    #expect(billing.freeSessionsRemaining == 3)
    #expect(billing.entitlement == .subscribed(expires: posts.monthly.expires, product: .monthly))
    #expect(!RootView.offersPaywall(billing))
  }

  @Test func aTransactionTheWorkerRefusesOffersThePaywallOnceTheFreeCountIsSpent() async throws {
    let host = "paywall-unconfirmed"
    GateProtocol.answer(host, "/v1/entitlement", 401, try posts.fixture("entitlement-refused"))
    let freeSessions = FreeSessions()
    let client = ProxyClient(
      baseURL: URL(string: "http://\(host)")!, session: GateProtocol.session(),
      attestor: EntitlementPostTests.FixedAttestor())
    let billing = BillingStore(
      freeSessions: freeSessions, attestor: EntitlementPostTests.FixedAttestor(),
      poster: .worker(client), transactions: EntitlementPostTests.Held(posts.monthly).source)

    await billing.refresh()
    await billing.confirm()
    #expect(billing.isUnconfirmed)
    #expect(billing.entitlement == .subscribed(expires: posts.monthly.expires, product: .monthly))
    #expect(!RootView.offersPaywall(billing))

    freeSessions.record(.refused(reason: "free-exhausted"))
    await billing.refresh()
    #expect(billing.freeSessionsRemaining == 0)
    #expect(billing.entitlement == .subscribed(expires: posts.monthly.expires, product: .monthly))
    #expect(RootView.offersPaywall(billing))
  }
}
