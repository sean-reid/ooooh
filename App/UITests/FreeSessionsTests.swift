import XCTest

/// The demo with `-free-exhausted 1`: the session runs under one line and without prompts, and
/// End brings up the paywall over the notes.
final class FreeSessionsTests: XCTestCase {
  @MainActor
  func testExhaustedSessionDark() {
    runExhausted(named: "exhausted-dark", arguments: ["-ui-color-scheme", "dark"])
  }

  @MainActor
  func testExhaustedSessionLight() {
    runExhausted(named: "exhausted-light", arguments: ["-ui-color-scheme", "light"])
  }

  @MainActor
  private func runExhausted(named name: String, arguments: [String]) {
    let app = XCUIApplication()
    app.launchArguments +=
      ["-onboardingComplete", "1", "-free-exhausted", "1"] + Worker.launchArguments + arguments
    app.launch()

    let demo = app.buttons["home.demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15))
    demo.tap()

    let line = app.staticTexts["session.quota"]
    XCTAssertTrue(line.waitForExistence(timeout: 15))
    XCTAssertEqual(line.label, "listening only, this month's free sessions are used up")
    XCTAssertTrue(app.staticTexts["session.elapsed"].exists)
    XCTAssertEqual(app.staticTexts["session.prompt"].label, "")
    attach(app.screenshot(), named: "\(name)-session")

    app.buttons["session.end"].tap()
    let paywall = app.staticTexts["Keep talking."]
    XCTAssertTrue(paywall.waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["Restore purchases"].exists)
    attach(app.screenshot(), named: "\(name)-paywall")

    app.buttons["Close"].tap()
    XCTAssertTrue(app.buttons["notes.done"].waitForExistence(timeout: 15))
    XCTAssertFalse(paywall.exists)
  }
}
