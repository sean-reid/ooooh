import Foundation
import Observation
import Proxy
import StoreKit

public enum BillingError: Error, Equatable {
  case productUnavailable(ProductID)
}

/// Loads the products, buys and restores, follows Transaction.updates, and reports one entitlement.
@MainActor @Observable
public final class BillingStore {
  public private(set) var plans: [Plan] = []
  public private(set) var entitlement: Entitlement
  public private(set) var isPurchasing = false
  /// The latest signed transaction as the Worker will verify it.
  public private(set) var latestTransactionJWS: String?
  /// Sessions left this month, as the Worker last reported. Only the free case shows it.
  public var freeSessionsRemaining: Int {
    didSet {
      if case .free = entitlement { entitlement = .free(remainingSessions: freeSessionsRemaining) }
    }
  }

  private var products: [ProductID: Product] = [:]
  private var updates: Task<Void, Never>?
  /// Its key id fixes the `appAccountToken` every purchase carries.
  private let attestor: (any Attestor)?

  public init(
    freeSessionsRemaining: Int = FreeTier.sessionsPerMonth, attestor: (any Attestor)? = nil
  ) {
    self.freeSessionsRemaining = freeSessionsRemaining
    self.attestor = attestor
    self.entitlement = .free(remainingSessions: freeSessionsRemaining)
    updates = Task { [weak self] in
      for await result in Transaction.updates {
        if case .verified(let transaction) = result { await transaction.finish() }
        await self?.refresh()
      }
    }
  }

  /// Fixed plans and nothing from StoreKit, for previews and snapshots.
  init(plans: [Plan]) {
    self.plans = plans
    attestor = nil
    freeSessionsRemaining = FreeTier.sessionsPerMonth
    entitlement = .free(remainingSessions: FreeTier.sessionsPerMonth)
  }

  isolated deinit { updates?.cancel() }

  public func load() async throws {
    let fetched = try await Product.products(for: ProductID.allCases.map(\.rawValue))
    products = Dictionary(
      uniqueKeysWithValues: fetched.compactMap { product in
        ProductID(rawValue: product.id).map { ($0, product) }
      })
    plans = ProductID.allCases.compactMap { products[$0].flatMap(Plan.init) }
    await refresh()
  }

  @discardableResult
  public func purchase(_ id: ProductID) async throws -> Entitlement {
    guard let product = products[id] else { throw BillingError.productUnavailable(id) }
    isPurchasing = true
    defer { isPurchasing = false }
    let token = AppAccountToken.forInstall(keyId: try await attestor?.keyId())
    switch try await product.purchase(options: [.appAccountToken(token)]) {
    case .success(let verification):
      let transaction = try verification.payloadValue
      await transaction.finish()
      await refresh()
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
    return entitlement
  }

  /// Re-derives the entitlement from StoreKit's current state.
  public func refresh() async {
    latestTransactionJWS = await latestTransaction()?.jwsRepresentation
    if let fromStatus = await entitlementFromStatus() {
      entitlement = fromStatus
    } else if let active = await activeEntitlement() {
      entitlement = active
    } else if let latest = await latestTransaction(), case .verified(let transaction) = latest,
      transaction.revocationDate != nil
    {
      entitlement = .revoked
    } else {
      entitlement = .free(remainingSessions: freeSessionsRemaining)
    }
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
        found = .inGrace
      case .revoked:
        if found == nil { found = .revoked }
      default:
        continue
      }
    }
    return found
  }

  private func activeEntitlement() async -> Entitlement? {
    for await result in Transaction.currentEntitlements {
      guard case .verified(let transaction) = result,
        let product = ProductID(rawValue: transaction.productID),
        transaction.revocationDate == nil
      else { continue }
      return .subscribed(expires: transaction.expirationDate, product: product)
    }
    return nil
  }

  private func latestTransaction() async -> VerificationResult<Transaction>? {
    var latest: VerificationResult<Transaction>?
    for id in ProductID.allCases {
      guard let result = await Transaction.latest(for: id.rawValue) else { continue }
      if let current = latest,
        current.unsafePayloadValue.purchaseDate >= result.unsafePayloadValue.purchaseDate
      {
        continue
      }
      latest = result
    }
    return latest
  }
}
