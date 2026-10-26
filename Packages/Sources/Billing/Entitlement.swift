import Foundation
import Proxy

/// What the user may do right now, from StoreKit and the Worker's answer to the last post.
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

/// The Worker's answer to the last transaction posted.
public enum Confirmation: Equatable, Sendable {
  /// Verified and held under this device.
  case confirmed(EntitlementResponse)
  /// Refused for `reason`, `wrong-device` when another install claimed the transaction first.
  case refused(reason: String)
}
