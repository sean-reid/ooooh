import XCTest

/// Settings from the home screen over a seeded store: the sheet, the paywall over it, and history
/// from the delete row, so they run without the Worker.
final class SettingsTests: XCTestCase {
  private let wait: TimeInterval = 15

  @MainActor
  func testSettingsDark() {
    runSettings(named: "settings-dark", arguments: ["-ui-color-scheme", "dark"])
  }

  @MainActor
  func testSettingsLight() {
    runSettings(named: "settings-light", arguments: ["-ui-color-scheme", "light"])
  }

  @MainActor
  func testSettingsAccessibilityExtraLarge() {
    runSettings(
      named: "settings-ax-xl",
      arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
  }

  @MainActor
  private func runSettings(named name: String, arguments: [String]) {
    let app = XCUIApplication()
    app.launchArguments +=
      ["-onboardingComplete", "1", "-reset-store", "1", "-seed-history", "1"] + arguments
    app.launch()

    let settings = app.buttons["home.settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: wait))
    XCTAssertEqual(settings.label, "Settings")
    XCTAssertGreaterThanOrEqual(settings.frame.width, 44)
    XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
    waitUntilHittable(settings)
    attach(app.screenshot(), named: "\(name)-home")
    settings.tap()

    let done = app.buttons["settings.done"]
    XCTAssertTrue(done.waitForExistence(timeout: wait))
    XCTAssertTrue(app.staticTexts["Settings"].exists)
    XCTAssertEqual(
      app.buttons["settings.deleteAll"].label, "Delete everything, 1 session on this phone")
    let version = app.descendants(matching: .any).matching(identifier: "settings.version")
    XCTAssertEqual(version.firstMatch.label, "Version, 0.1.0 (1)")
    attach(app.screenshot(), named: "\(name)-settings")

    let subscribe = app.buttons["settings.subscribe"]
    scrollUntilHittable(subscribe, in: app)
    subscribe.tap()
    let paywall = app.staticTexts["Keep talking."]
    XCTAssertTrue(paywall.waitForExistence(timeout: wait))
    XCTAssertTrue(app.buttons["Restore purchases"].exists)
    let plans = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Monthly,' OR label BEGINSWITH 'Yearly,'"))
    if plans.count > 0 { XCTAssertEqual(plans.count, 2) }
    attach(app.screenshot(), named: "\(name)-paywall")
    app.buttons["Close"].tap()
    XCTAssertTrue(paywall.waitForNonExistence(timeout: wait))

    let history = app.buttons["settings.history"]
    scrollUntilHittable(history, in: app)
    history.tap()
    let list = app.collectionViews["history.list"]
    waitUntilHittable(list)
    let row = list.buttons.containing(
      NSPredicate(format: "label BEGINSWITH %@", "Carver Street or the park,")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: wait))
    attach(app.screenshot(), named: "\(name)-history")
    app.buttons["history.done"].tap()
    XCTAssertTrue(list.waitForNonExistence(timeout: wait))

    waitUntilHittable(done)
    done.tap()
    waitUntilHittable(settings)
    XCTAssertFalse(done.exists)
  }
}
