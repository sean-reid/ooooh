import XCTest

extension XCTestCase {
  /// The paywall's plan buttons once the store has answered: two plans, or the line that none
  /// loaded. Until then the cards are a redacted placeholder, which no audit should read.
  @MainActor
  func waitForPlans(in app: XCUIApplication) -> XCUIElementQuery {
    let plans = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Monthly,' OR label BEGINSWITH 'Yearly,'"))
    let none = app.staticTexts["The plans couldn't be loaded."]
    wait(until: { plans.count == 2 || none.exists }, "the paywall never settled on its plans")
    return plans
  }
}
