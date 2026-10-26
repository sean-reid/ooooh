import Foundation
import StoreKit

/// One verified transaction as the store reads it: the JWS the Worker verifies and what it says.
public struct SignedTransaction: Equatable, Sendable {
  public var jws: String
  public var product: ProductID
  public var purchaseDate: Date
  public var expires: Date?
  public var revoked: Bool

  public init(
    jws: String, product: ProductID, purchaseDate: Date, expires: Date?, revoked: Bool
  ) {
    self.jws = jws
    self.product = product
    self.purchaseDate = purchaseDate
    self.expires = expires
    self.revoked = revoked
  }

  init?(_ result: VerificationResult<Transaction>) {
    guard case .verified(let transaction) = result,
      let product = ProductID(rawValue: transaction.productID)
    else { return nil }
    self.init(
      jws: result.jwsRepresentation, product: product, purchaseDate: transaction.purchaseDate,
      expires: transaction.expirationDate, revoked: transaction.revocationDate != nil)
  }
}

/// Where the transactions come from: StoreKit on a device, fixed values in tests.
public struct TransactionSource: Sendable {
  /// The newest verified transaction for either product, whatever its state.
  public var latest: @Sendable () async -> SignedTransaction?
  /// The verified transaction that entitles the device now, nil when none does.
  public var current: @Sendable () async -> SignedTransaction?
  /// Every verified transaction StoreKit delivers while the app runs, each finished first.
  public var updates: @Sendable () -> AsyncStream<SignedTransaction>

  public init(
    latest: @escaping @Sendable () async -> SignedTransaction?,
    current: @escaping @Sendable () async -> SignedTransaction?,
    updates: @escaping @Sendable () -> AsyncStream<SignedTransaction>
  ) {
    self.latest = latest
    self.current = current
    self.updates = updates
  }

  public static let storeKit = TransactionSource(
    latest: {
      var latest: SignedTransaction?
      for id in ProductID.allCases {
        guard let result = await Transaction.latest(for: id.rawValue),
          let signed = SignedTransaction(result)
        else { continue }
        if let current = latest, current.purchaseDate >= signed.purchaseDate { continue }
        latest = signed
      }
      return latest
    },
    current: {
      for await result in Transaction.currentEntitlements {
        if let signed = SignedTransaction(result), !signed.revoked { return signed }
      }
      return nil
    },
    updates: {
      AsyncStream { continuation in
        let task = Task {
          for await result in Transaction.updates {
            if case .verified(let transaction) = result { await transaction.finish() }
            if let signed = SignedTransaction(result) { continuation.yield(signed) }
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    })

  /// No transactions and none to come.
  public static let none = TransactionSource(
    latest: { nil }, current: { nil }, updates: { AsyncStream { $0.finish() } })
}
