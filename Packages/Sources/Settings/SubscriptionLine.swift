import Billing
import Foundation

extension Entitlement {
  /// What the Subscription row in Settings says. The renewal date carries its year only when
  /// that year is not `now`'s.
  public func settingsLine(
    now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
  ) -> String {
    switch self {
    case .free:
      return "Subscribe"
    case .revoked:
      return "Subscription ended"
    case .inGrace(let product):
      return "\(product.name), payment being retried"
    case .subscribed(let expires, let product):
      guard let expires else { return product.name }
      var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        .month(.wide).day()
      if calendar.component(.year, from: expires) != calendar.component(.year, from: now) {
        style = style.year()
      }
      return "\(product.name), renews \(expires.formatted(style))"
    }
  }

  /// The footer under the Subscription section, only while Apple holds the subscription.
  public var settingsFooter: String? {
    isPaid ? "Managed through the App Store." : nil
  }
}
