import Foundation

/// What the user may do right now, derived from StoreKit alone.
public enum Entitlement: Equatable, Sendable {
  case free(remainingSessions: Int)
  case subscribed(expires: Date?, product: ProductID)
  case inGrace
  case revoked

  /// Grace counts as paid: Apple keeps access on while the card is retried.
  public var isPaid: Bool {
    switch self {
    case .subscribed, .inGrace: true
    case .free, .revoked: false
    }
  }
}
