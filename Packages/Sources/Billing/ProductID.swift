/// The two subscriptions, one group. App Store Connect gets the same ids later.
public enum ProductID: String, CaseIterable, Sendable {
  case monthly = "com.seanreid.ooooh.monthly"
  case yearly = "com.seanreid.ooooh.yearly"

  public static let subscriptionGroup = "ooooh.listener"

  public var name: String {
    switch self {
    case .monthly: "Monthly"
    case .yearly: "Yearly"
    }
  }

  var period: String {
    switch self {
    case .monthly: "a month"
    case .yearly: "a year"
    }
  }
}

/// What the free tier allows. The Worker counts sessions; these are the limits it applies.
public enum FreeTier {
  public static let sessionsPerMonth = 3
  public static let promptMinutesPerSession = 20
}
