import XCTest

final class LaunchTests: XCTestCase {
  @MainActor
  func testLaunchShowsListener() {
    let app = XCUIApplication()
    app.launchArguments += ["-onboardingComplete", "1"]
    app.launch()
    XCTAssertTrue(app.staticTexts["ooooh"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.otherElements["Your listener, resting"].exists
        || app.images["Your listener, resting"].exists)
  }
}
