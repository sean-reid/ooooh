import XCTest

/// Settings from the home screen over a seeded store: the sheet, the paywall over it, and history
/// from the delete row, so they run without the Worker.
final class SettingsTests: UITestCase {
  @MainActor
  func testSettingsDark() throws {
    try runSettings(named: "settings-dark", arguments: ["-ui-color-scheme", "dark"])
  }

  @MainActor
  func testSettingsLight() throws {
    try runSettings(named: "settings-light", arguments: ["-ui-color-scheme", "light"])
  }

  @MainActor
  func testSettingsAccessibilityExtraLarge() throws {
    try runSettings(
      named: "settings-ax-xl",
      arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
  }

  @MainActor
  private func runSettings(named name: String, arguments: [String]) throws {
    let app = XCUIApplication()
    app.launchArguments +=
      ["-onboardingComplete", "1", "-reset-store", "1", "-seed-history", "1"] + arguments
    app.launch()

    let settings = app.buttons["home.settings"]
    waitUntilHittable(settings)
    XCTAssertEqual(settings.label, "Settings")
    XCTAssertGreaterThanOrEqual(settings.frame.width, 44)
    XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
    attach(app, named: "\(name)-home")
    try auditAccessibility(app, named: "\(name)-home")
    settings.tap()

    let done = app.buttons["settings.done"]
    XCTAssertTrue(done.appears())
    XCTAssertTrue(app.staticTexts["Settings"].exists)
    XCTAssertEqual(
      app.buttons["settings.deleteAll"].label, "Delete everything, 1 session on this phone")
    let version = app.descendants(matching: .any).matching(identifier: "settings.version")
    XCTAssertNotNil(
      version.firstMatch.label.wholeMatch(of: /Version, \d+\.\d+\.\d+ \(\d+\)/),
      version.firstMatch.label)
    attach(app, named: "\(name)-settings")
    try auditAccessibility(app, named: "\(name)-settings")

    let subscribe = app.buttons["settings.subscribe"]
    scrollUntilHittable(subscribe, in: app)
    subscribe.tap()
    let paywall = app.staticTexts["Keep talking."]
    XCTAssertTrue(paywall.appears())
    XCTAssertTrue(app.buttons["Restore purchases"].exists)
    let plans = waitForPlans(in: app)
    if plans.count > 0 { XCTAssertEqual(plans.count, 2) }
    attach(app, named: "\(name)-paywall")
    try auditAccessibility(app, named: "\(name)-paywall")
    app.buttons["Close"].tap()
    XCTAssertTrue(paywall.disappears())

    let history = app.buttons["settings.history"]
    scrollUntilHittable(history, in: app)
    history.tap()
    let list = app.collectionViews["history.list"]
    waitUntilHittable(list)
    let row = list.buttons.containing(
      NSPredicate(format: "label BEGINSWITH %@", "Carver Street or the park,")
    ).firstMatch
    XCTAssertTrue(row.appears())
    attach(app, named: "\(name)-history")
    app.buttons["history.done"].tap()
    XCTAssertTrue(list.disappears())

    let privacy = app.buttons["What leaves your phone, and what stays"]
    scrollUntilHittable(privacy, in: app)
    privacy.tap()
    let policy = app.staticTexts["What my server keeps"]
    XCTAssertTrue(policy.appears())
    attach(app, named: "\(name)-privacy")
    try auditAccessibility(app, named: "\(name)-privacy")
    let back = app.navigationBars.buttons["Back"]
    waitUntilHittable(back)
    back.tap()
    XCTAssertTrue(policy.disappears())

    waitUntilHittable(done)
    done.tap()
    XCTAssertTrue(done.disappears())
    waitUntilHittable(settings)
  }
}
