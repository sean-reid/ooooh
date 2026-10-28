import Foundation
import OSLog
import Observation
import Proxy
import StoreKit

public enum BillingError: Error, Equatable, LocalizedError {
  case productUnavailable(ProductID)
  /// The App Store took the purchase but has not answered within the wait.
  case appStoreUnresponsive
  /// The purchase waits on someone else, as with Ask to Buy.
  case purchasePending

  public var errorDescription: String? {
    switch self {
    case .productUnavailable: "That plan isn't available right now."
    case .appStoreUnresponsive:
      "The App Store didn't answer. Try again in a moment; a purchase that goes through later still counts."
    case .purchasePending:
      "The purchase is waiting for approval. It counts as soon as it's approved."
    }
  }
}

/// Loads the products, buys and restores, follows the transactions and posts each one to the
/// Worker, and reports one entitlement.
@MainActor @Observable
public final class BillingStore {
  public private(set) var plans: [Plan] = []
  /// True once a load has finished, so an empty `plans` means StoreKit returned none.
  public private(set) var hasLoadedPlans: Bool
  public private(set) var entitlement: Entitlement
  public private(set) var isPurchasing = false
  /// The latest verified transaction as the Worker verifies it.
  public private(set) var latestTransactionJWS: String?
  /// The Worker's answer to the last post. Nil until it answers this launch, and still nil after
  /// a post that never reached it, which the next launch repeats.
  public private(set) var confirmation: Confirmation?
  /// Sessions left this month, as the Worker last reported. Only the free case shows it.
  public var freeSessionsRemaining: Int {
    didSet {
      if case .free = entitlement { entitlement = .free(remainingSessions: freeSessionsRemaining) }
    }
  }

  private var products: [ProductID: Product] = [:]
  private var latest: SignedTransaction?
  private var updates: Task<Void, Never>?
  /// Its key id fixes the `appAccountToken` every purchase carries.
  private let attestor: (any Attestor)?
  private let freeSessions: (any FreeSessionCount)?
  private let poster: EntitlementPoster?
  private let transactions: TransactionSource
  /// How long a purchase may hold the paywall before it is told the App Store did not answer.
  private let purchaseWait: Duration
  /// A purchase the paywall stopped waiting for, kept so its answer is still settled.
  private var latePurchase: Task<Void, Never>?
  private static let log = Logger(subsystem: "com.seanreid.ooooh", category: "billing")

  public init(
    freeSessions: (any FreeSessionCount)? = nil,
    freeSessionsRemaining: Int = FreeTier.sessionsPerMonth,
    attestor: (any Attestor)? = nil,
    poster: EntitlementPoster? = nil,
    transactions: TransactionSource = .storeKit,
    purchaseWait: Duration = .seconds(30)
  ) {
    self.freeSessions = freeSessions
    self.freeSessionsRemaining = freeSessionsRemaining
    self.attestor = attestor
    self.poster = poster
    self.transactions = transactions
    self.purchaseWait = purchaseWait
    self.hasLoadedPlans = false
    self.entitlement = .free(remainingSessions: freeSessionsRemaining)
    updates = Task { [weak self] in
      for await transaction in transactions.updates() {
        await self?.refresh()
        await self?.confirm(transaction.jws)
      }
    }
  }

  /// Fixed plans and nothing from StoreKit, for previews and snapshots.
  init(plans: [Plan], hasLoadedPlans: Bool = true, confirmation: Confirmation? = nil) {
    self.plans = plans
    self.hasLoadedPlans = hasLoadedPlans
    self.confirmation = confirmation
    attestor = nil
    freeSessions = nil
    poster = nil
    transactions = .none
    purchaseWait = .seconds(30)
    freeSessionsRemaining = FreeTier.sessionsPerMonth
    entitlement = .free(remainingSessions: FreeTier.sessionsPerMonth)
  }

  isolated deinit { updates?.cancel() }

  /// True once the Worker refused the latest transaction, so it counts this device as free.
  public var isUnconfirmed: Bool {
    if case .refused = confirmation { return true }
    return false
  }

  /// The products, then the entitlement, then one post of the latest transaction so a Worker that
  /// lost this device's record gets it back. A failed product fetch still posts.
  public func load() async throws {
    var failure: (any Error)?
    do {
      try await loadPlans()
    } catch {
      failure = error
    }
    await refresh()
    await confirm()
    if let failure { throw failure }
  }

  /// Buys `id`. The StoreKit call cannot be cancelled, so after `purchaseWait` the paywall is
  /// released with `appStoreUnresponsive` and the call's eventual answer is settled in the
  /// background; `Transaction.updates` covers it as well.
  @discardableResult
  public func purchase(_ id: ProductID) async throws -> Entitlement {
    let token = AppAccountToken.forInstall(keyId: try await attestor?.keyId())
    guard let product = products[id] else { throw BillingError.productUnavailable(id) }
    isPurchasing = true
    defer { isPurchasing = false }
    Self.log.info("Purchasing \(id.rawValue, privacy: .public)")
    let call = Task { try await product.purchase(options: [.appAccountToken(token)]) }
    let wait = purchaseWait
    let answer = try await withThrowingTaskGroup(of: Product.PurchaseResult?.self) { group in
      group.addTask { try await call.value }
      group.addTask {
        try await Task.sleep(for: wait)
        return nil
      }
      defer { group.cancelAll() }
      return try await group.next() ?? nil
    }
    guard let answer else {
      Self.log.error("Purchase of \(id.rawValue, privacy: .public) has no answer after \(wait)")
      latePurchase = Task { [weak self] in
        guard let result = try? await call.value else { return }
        try? await self?.settle(result, of: id)
      }
      throw BillingError.appStoreUnresponsive
    }
    try await settle(answer, of: id)
    return entitlement
  }

  private func settle(_ result: Product.PurchaseResult, of id: ProductID) async throws {
    switch result {
    case .success(let verification):
      let transaction = try verification.payloadValue
      Self.log.info("Purchase of \(id.rawValue, privacy: .public) succeeded")
      await transaction.finish()
      await refresh()
      await confirm(verification.jwsRepresentation)
    case .pending:
      Self.log.info("Purchase of \(id.rawValue, privacy: .public) is pending")
      throw BillingError.purchasePending
    case .userCancelled:
      Self.log.info("Purchase of \(id.rawValue, privacy: .public) cancelled")
    @unknown default:
      Self.log.error("Purchase of \(id.rawValue, privacy: .public) returned an unknown result")
    }
  }

  @discardableResult
  public func restore() async throws -> Entitlement {
    try await AppStore.sync()
    await refresh()
    await confirm()
    return entitlement
  }

  /// Re-derives the entitlement from StoreKit, the Worker's free count, and its last answer.
  public func refresh() async {
    if let remaining = await freeSessions?.remainingFreeSessions {
      freeSessionsRemaining = remaining
    }
    latest = await transactions.latest()
    latestTransactionJWS = latest?.jws
    entitlement = reconcile(await storeKitEntitlement())
  }

  /// Posts `jws`, else the latest verified transaction, and takes the Worker's answer over
  /// StoreKit's. A 401 keeps StoreKit's view and the reason; a post that never arrives changes
  /// nothing.
  public func confirm(_ jws: String? = nil) async {
    guard let poster, let jws = jws ?? latestTransactionJWS else { return }
    do {
      confirmation = .confirmed(try await poster.post(jws))
    } catch ProxyError.unauthorized(let reason) {
      confirmation = .refused(reason: reason)
      Self.log.error("Entitlement refused: \(reason, privacy: .public)")
    } catch {
      Self.log.error("Entitlement post failed: \(String(describing: error), privacy: .public)")
      return
    }
    entitlement = reconcile(await storeKitEntitlement())
  }

  private func loadPlans() async throws {
    hasLoadedPlans = false
    defer { hasLoadedPlans = true }
    let fetched = try await Product.products(for: ProductID.allCases.map(\.rawValue))
    products = Dictionary(
      uniqueKeysWithValues: fetched.compactMap { product in
        ProductID(rawValue: product.id).map { ($0, product) }
      })
    plans = ProductID.allCases.compactMap { products[$0].flatMap(Plan.init) }
  }

  /// The Worker's answer over StoreKit's: its expiry when it says paid, free when it says free.
  /// StoreKit's grace and revocation stand, since the Worker read them off the same transaction.
  private func reconcile(_ local: Entitlement) -> Entitlement {
    guard case .confirmed(let response)? = confirmation else { return local }
    switch (response.entitlement, local) {
    case (.paid, .inGrace), (.free, .revoked):
      return local
    case (.paid, _):
      guard let product = latest?.product else { return local }
      return .subscribed(expires: response.expiresDate, product: product)
    case (.free, _):
      return .free(remainingSessions: freeSessionsRemaining)
    }
  }

  private func storeKitEntitlement() async -> Entitlement {
    if let fromStatus = await entitlementFromStatus() { return fromStatus }
    if let current = await transactions.current() {
      return .subscribed(expires: current.expires, product: current.product)
    }
    if latest?.revoked == true { return .revoked }
    return .free(remainingSessions: freeSessionsRemaining)
  }

  private func entitlementFromStatus() async -> Entitlement? {
    guard let subscription = products.values.first?.subscription,
      let statuses = try? await subscription.status
    else { return nil }
    var found: Entitlement?
    for status in statuses {
      switch status.state {
      case .subscribed:
        guard case .verified(let transaction) = status.transaction,
          let product = ProductID(rawValue: transaction.productID)
        else { continue }
        return .subscribed(expires: transaction.expirationDate, product: product)
      case .inGracePeriod:
        guard case .verified(let transaction) = status.transaction,
          let product = ProductID(rawValue: transaction.productID)
        else { continue }
        found = .inGrace(product: product)
      case .revoked:
        if found == nil { found = .revoked }
      default:
        continue
      }
    }
    return found
  }
}
