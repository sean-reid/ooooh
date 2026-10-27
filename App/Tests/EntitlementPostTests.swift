import Billing
import Foundation
import Proxy
import Synchronization
import TestSupport
import Testing

@testable import ooooh

/// A store posting through a real `ProxyClient` to `GateProtocol`, which answers with what the
/// Worker wrote to Packages/Tests/ProxyTests/Fixtures. Each test has its own host.
@MainActor
@Suite struct EntitlementPostTests {
  /// Signs every request from one fixed key.
  struct FixedAttestor: Attestor {
    func assertion(clientDataHash: Data) async throws -> Assertion? {
      Assertion(keyId: "key-1", assertion: Data([0xa2, 0x01, 0x02]))
    }

    func keyId() async throws -> String? { "key-1" }
  }

  /// The transactions as the test sets them, read by the store on each refresh, with a stream it
  /// feeds by hand.
  final class Held: Sendable {
    let transaction: Mutex<SignedTransaction?>
    let updates: AsyncStream<SignedTransaction>
    let deliver: AsyncStream<SignedTransaction>.Continuation

    init(_ transaction: SignedTransaction?) {
      self.transaction = Mutex(transaction)
      (updates, deliver) = AsyncStream.makeStream()
    }

    var source: TransactionSource {
      TransactionSource(
        latest: { self.transaction.withLock { $0 } },
        current: { self.transaction.withLock { $0.flatMap { $0.revoked ? nil : $0 } } },
        updates: { self.updates })
    }
  }

  let jws = "eyJhbGciOiJFUzI1NiJ9.eyJwcm9kdWN0SWQiOiJtb250aGx5In0.c2ln"
  let renewalJWS = "eyJhbGciOiJFUzI1NiJ9.eyJwcm9kdWN0SWQiOiJyZW5ld2FsIn0.c2ln"
  let paidUntil = Date(timeIntervalSince1970: 4_070_908_800)

  var monthly: SignedTransaction {
    SignedTransaction(
      jws: jws, product: .monthly, purchaseDate: Date(timeIntervalSince1970: 1_761_000_000),
      expires: Date(timeIntervalSince1970: 1_763_600_000), revoked: false)
  }

  /// A store whose poster is a real client against `host`, signing with `FixedAttestor`.
  func store(_ host: String, transactions: TransactionSource) -> BillingStore {
    let client = ProxyClient(
      baseURL: URL(string: "http://\(host)")!, session: GateProtocol.session(),
      attestor: FixedAttestor())
    return BillingStore(
      attestor: FixedAttestor(), poster: .worker(client), transactions: transactions)
  }

  func transactions(posted host: String) throws -> [String] {
    try GateProtocol.requests(to: host).map { request in
      #expect(request.path == "/v1/entitlement")
      let body = try JSONSerialization.jsonObject(with: request.body) as? [String: String]
      return try #require(body?["transaction"])
    }
  }

  @Test func aLaunchPostsTheTransactionSignedOnceAndTakesTheWorkersView() async throws {
    let host = "entitled.test"
    GateProtocol.answer(
      host, "/v1/entitlement", 200, try Bundle.tests.fixture("entitlement-paid.json"))
    let store = store(host, transactions: Held(monthly).source)

    try? await store.load()

    #expect(try transactions(posted: host) == [jws])
    let request = try #require(GateProtocol.requests(to: host).first)
    #expect(request.header("x-device") == "key-1")
    #expect(request.header("x-assertion") == "ogEC")
    #expect(request.header("x-assertion-time").flatMap(Int.init) != nil)
    #expect(
      store.confirmation
        == .confirmed(EntitlementResponse(entitlement: .paid, expiresDate: paidUntil)))
    #expect(store.entitlement == .subscribed(expires: paidUntil, product: .monthly))
    #expect(!store.isUnconfirmed)

    await store.refresh()
    #expect(store.entitlement == .subscribed(expires: paidUntil, product: .monthly))
    #expect(GateProtocol.requests(to: host).count == 1)
  }

  @Test func aLaunchWithNoTransactionPostsNothing() async throws {
    let host = "fresh.test"
    GateProtocol.answer(
      host, "/v1/entitlement", 200, try Bundle.tests.fixture("entitlement-paid.json"))
    let store = store(host, transactions: .none)

    try? await store.load()

    #expect(GateProtocol.requests(to: host).isEmpty)
    #expect(store.confirmation == nil)
    #expect(store.entitlement == .free(remainingSessions: 3))
  }

  @Test func aRefusalKeepsStoreKitsViewAndTheReason() async throws {
    let host = "refused.test"
    GateProtocol.answer(
      host, "/v1/entitlement", 401, try Bundle.tests.fixture("entitlement-refused.json"))
    let store = store(host, transactions: Held(monthly).source)

    try? await store.load()

    #expect(try transactions(posted: host) == [jws])
    #expect(store.confirmation == .refused(reason: "wrong-device"))
    #expect(store.isUnconfirmed)
    #expect(store.entitlement == .subscribed(expires: monthly.expires, product: .monthly))
  }

  @Test func aFreeAnswerOutranksACurrentStoreKitEntitlement() async throws {
    let host = "lapsed.test"
    GateProtocol.answer(
      host, "/v1/entitlement", 200, try Bundle.tests.fixture("entitlement-free.json"))
    let store = store(host, transactions: Held(monthly).source)

    try? await store.load()

    #expect(
      store.confirmation
        == .confirmed(
          EntitlementResponse(
            entitlement: .free, expiresDate: Date(timeIntervalSince1970: 1_780_272_000))))
    #expect(store.entitlement == .free(remainingSessions: 3))
    #expect(!store.isUnconfirmed)
  }

  @Test func aWorkerThatDoesNotAnswerLeavesStoreKitsViewForTheNextLaunch() async throws {
    let host = "down.test"
    GateProtocol.answer(host, "/v1/entitlement", 503, Data(#"{"retryAfter":1}"#.utf8))
    let store = store(host, transactions: Held(monthly).source)

    try? await store.load()

    #expect(try transactions(posted: host) == [jws])
    #expect(store.confirmation == nil)
    #expect(store.entitlement == .subscribed(expires: monthly.expires, product: .monthly))
  }

  @Test func eachTransactionStoreKitDeliversIsPosted() async throws {
    let host = "renewing.test"
    GateProtocol.answer(
      host, "/v1/entitlement", 200, try Bundle.tests.fixture("entitlement-paid.json"))
    let held = Held(nil)
    let store = store(host, transactions: held.source)
    #expect(store.entitlement == .free(remainingSessions: 3))

    held.transaction.withLock { $0 = monthly }
    held.deliver.yield(monthly)
    await wait { store.entitlement == .subscribed(expires: paidUntil, product: .monthly) }
    #expect(store.entitlement == .subscribed(expires: paidUntil, product: .monthly))
    #expect(GateProtocol.requests(to: host).count == 1)

    var renewal = monthly
    renewal.jws = renewalJWS
    held.transaction.withLock { $0 = renewal }
    held.deliver.yield(renewal)
    await wait {
      GateProtocol.requests(to: host).count == 2 && store.latestTransactionJWS == renewalJWS
    }
    #expect(try transactions(posted: host) == [jws, renewalJWS])
    #expect(store.latestTransactionJWS == renewalJWS)
  }

  @Test func theSimulatorHasNoPoster() {
    #expect(AppBilling.poster == nil)
  }
}
