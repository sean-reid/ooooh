import Foundation
import OSLog
import Observation
import Proxy
import StoreKit

public enum BillingError: Error, Equatable {
  case productUnavailable(ProductID)
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
  private static let log = Logger(subsystem: "com.seanreid.ooooh", category: "billing")

  public init(
    freeSessions: (any FreeSessionCount)? = nil,
    freeSessionsRemaining: Int = FreeTier.sessionsPerMonth,
    attestor: (any Attestor)? = nil,
    poster: EntitlementPoster? = nil,
    transactions: TransactionSource = .storeKit
  ) {
    self.freeSessions = freeSessions
    self.freeSessionsRemaining = freeSessionsRemaining
    self.attestor = attestor
    self.poster = poster
    self.transactions = transactions
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

  @discardableResult
  public func purchase(_ id: ProductID) async throws -> Entitlement {
    let token = AppAccountToken.forInstall(keyId: try await attestor?.keyId())
    guard let product = products[id] else { throw BillingError.productUnavailable(id) }
    isPurchasing = true
    defer { isPurchasing = false }
    switch try await product.purchase(options: [.appAccountToken(token)]) {
    case .success(let verification):
      let transaction = try verification.payloadValue
      await transaction.finish()
      await refresh()
      await confirm(verification.jwsRepresentation)
    case .pending, .userCancelled:
      break
    @unknown default:
      break
    }
    return entitlement
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
