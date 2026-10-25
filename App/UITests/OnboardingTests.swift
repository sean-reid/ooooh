import XCTest

final class OnboardingTests: XCTestCase {
  @MainActor
  func testWalksTheThreeScreensToStart() {
    let app = XCUIApplication()
    app.launchArguments += ["-onboarding", "1"]
    app.launch()

    XCTAssertTrue(app.staticTexts["Think out loud."].waitForExistence(timeout: 5))
    attach(app, named: "onboarding-1")

    app.swipeLeft()
    XCTAssertTrue(app.staticTexts["It waits."].waitForExistence(timeout: 5))
    attach(app, named: "onboarding-2")

    let next = app.buttons["onboarding.next"]
    XCTAssertGreaterThanOrEqual(next.frame.height, 44)
    next.tap()

    let start = app.buttons["onboarding.start"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    XCTAssertEqual(start.label, "Start a session")
    XCTAssertGreaterThanOrEqual(start.frame.height, 44)
    XCTAssertFalse(app.buttons["onboarding.next"].exists)
    attach(app, named: "onboarding-3")
  }

  @MainActor
  private func attach(_ app: XCUIApplication, named name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
