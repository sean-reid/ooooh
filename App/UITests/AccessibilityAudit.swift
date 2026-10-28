import XCTest

extension UITestCase {
  /// Every audit category over the screen as it stands, under `name` in the result bundle.
  /// Each finding fails the test and prints what it was on; `ignores` names the ones the audit
  /// gets wrong.
  @MainActor
  func auditAccessibility(_ app: XCUIApplication, named name: String) throws {
    try XCTContext.runActivity(named: "accessibility audit \(name)") { _ in
      try app.performAccessibilityAudit(for: .all) { issue in
        let ignored = Self.ignores(issue, offScreen: app.frame)
        print(
          "audit \(name) \(ignored ? "ignored" : "finding") \(issue.auditType.rawValue): "
            + "\(issue.detailedDescription) on \(issue.element.map(String.init(describing:)) ?? "no element") "
            + "at \(issue.element?.frame ?? .null)"
        )
        return ignored
      }
    }
  }

  /// The audit's false positives: the system keyboard's prediction cells, which the audit walks
  /// while a field has focus and which carry no description the app can give them, and a
  /// contrast reading on an element scrolled partly or wholly past `screen` or under the
  /// keyboard, where the pixels sampled are not the element's.
  nonisolated static func ignores(_ issue: XCUIAccessibilityAuditIssue, offScreen screen: CGRect)
    -> Bool
  {
    switch issue.auditType {
    case .sufficientElementDescription:
      return issue.detailedDescription.contains("TUIPredictionViewCell")
    case .contrast:
      guard let element = issue.element else { return false }
      return !screen.contains(element.frame) || !element.isHittable
    default:
      return false
    }
  }
}
