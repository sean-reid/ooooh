import XCTest

final class LaunchTests: UITestCase {
  @MainActor
  func testLaunchShowsListener() {
    let app = XCUIApplication()
    app.launchArguments += ["-onboardingComplete", "1"]
    app.launch()
    XCTAssertTrue(app.staticTexts["ooooh"].appears())
    XCTAssertTrue(app.descendants(matching: .any)["Your listener, resting"].firstMatch.appears())
  }
}
