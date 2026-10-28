import XCTest

/// The demo with `-free-exhausted 1` at 16x: the session runs under one line and without
/// prompts, and when the fixture runs out the paywall comes up over a notes screen that says why
/// there are none.
final class FreeSessionsTests: UITestCase {
  @MainActor
  func testExhaustedSessionDark() throws {
    try runExhausted(named: "exhausted-dark", arguments: ["-ui-color-scheme", "dark"])
  }

  @MainActor
  func testExhaustedSessionLight() throws {
    try runExhausted(named: "exhausted-light", arguments: ["-ui-color-scheme", "light"])
  }

  @MainActor
  private func runExhausted(named name: String, arguments: [String]) throws {
    let app = XCUIApplication()
    app.launchArguments +=
      ["-onboardingComplete", "1", "-free-exhausted", "1", "-demo-speed", "16"]
      + Worker.launchArguments + arguments
    app.launch()

    let demo = app.buttons["home.demo"]
    waitUntilHittable(demo)
    demo.tap()

    let line = app.staticTexts["session.quota"]
    XCTAssertTrue(line.appears())
    XCTAssertEqual(line.label, "listening only, this month's free sessions are used up")
    XCTAssertTrue(app.staticTexts["session.elapsed"].exists)
    XCTAssertEqual(app.staticTexts["session.prompt"].label, "")
    XCTAssertTrue(app.buttons["session.end"].exists)
    attach(app, named: "\(name)-session")
    try auditAccessibility(app, named: "\(name)-session")

    let paywall = app.staticTexts["Keep talking."]
    XCTAssertTrue(paywall.appears())
    XCTAssertTrue(app.buttons["Restore purchases"].exists)
    _ = waitForPlans(in: app)
    attach(app, named: "\(name)-paywall")
    try auditAccessibility(app, named: "\(name)-paywall")

    app.buttons["Close"].tap()
    XCTAssertTrue(paywall.disappears())
    waitUntilHittable(app.buttons["notes.done"])
    XCTAssertEqual(
      app.staticTexts["notes.pending.line"].label,
      "This month's free sessions are used up, so there are no notes for this one.")
    attach(app, named: "\(name)-notes")
    try auditAccessibility(app, named: "\(name)-notes")
  }
}
