import XCTest

final class OnboardingTests: UITestCase {
  @MainActor
  func testWalksTheThreeScreensToStart() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-onboarding", "1"]
    app.launch()

    XCTAssertTrue(app.staticTexts["Think out loud."].appears())
    attach(app, named: "onboarding-1")
    try auditAccessibility(app, named: "onboarding-1")

    app.swipeLeft()
    XCTAssertTrue(app.staticTexts["It waits."].appears())
    attach(app, named: "onboarding-2")
    try auditAccessibility(app, named: "onboarding-2")

    let next = app.buttons["onboarding.next"]
    waitUntilHittable(next)
    XCTAssertGreaterThanOrEqual(next.frame.height, 44)
    next.tap()

    let start = app.buttons["onboarding.start"]
    XCTAssertTrue(start.appears())
    XCTAssertEqual(start.label, "Start a session")
    XCTAssertGreaterThanOrEqual(start.frame.height, 44)
    XCTAssertFalse(app.buttons["onboarding.next"].exists)
    attach(app, named: "onboarding-3")
    try auditAccessibility(app, named: "onboarding-3")
  }
}
