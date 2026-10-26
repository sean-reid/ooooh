import XCTest

/// The moments the store screenshots need, with the Demo row hidden, each held three seconds so
/// a screen recording of the run has a shot to cut. The session test runs the demo against a
/// Worker, tools/store/worker.mjs or a real one, and skips when nothing answers at its URL.
final class StoreCaptureTests: XCTestCase {
  private let common =
    ["-onboardingComplete", "1", "-reset-store", "1", "-hide-debug", "1"]
    + ["-ui-color-scheme", "dark"]
  private let hold: Duration = .seconds(3)

  @MainActor
  func testHomeWithCarryover() async {
    let app = XCUIApplication()
    app.launchArguments += common + ["-seed-history", "1"]
    app.launch()
    let card = app.otherElements["home.carryover"]
    XCTAssertTrue(card.waitForExistence(timeout: 15))
    XCTAssertFalse(app.buttons["home.demo"].exists)
    try? await Task.sleep(for: hold)
    attach(app.screenshot(), named: "store-carryover")
  }

  @MainActor
  func testOnboardingQuietMode() async {
    let app = XCUIApplication()
    app.launchArguments += common + ["-onboarding", "1"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Think out loud."].waitForExistence(timeout: 15))
    try? await Task.sleep(for: hold)
    app.swipeLeft()
    XCTAssertTrue(app.staticTexts["It waits."].waitForExistence(timeout: 15))
    try? await Task.sleep(for: hold)
    attach(app.screenshot(), named: "store-quiet")
  }

  @MainActor
  func testSettingsDataControls() async {
    let app = XCUIApplication()
    app.launchArguments += common + ["-seed-history", "1"]
    app.launch()
    let settings = app.buttons["home.settings"]
    waitUntilHittable(settings)
    settings.tap()
    XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["settings.deleteAll"].exists)
    try? await Task.sleep(for: hold)
    attach(app.screenshot(), named: "store-settings")
  }

  /// The orb listening before anything is asked, speaking with the question beneath it, listening
  /// again with the question left beside it, and the notes.
  @MainActor
  func testSessionMoments() async throws {
    try await requireWorker()
    let app = XCUIApplication()
    app.launchArguments += common + ["-demo", "1"] + Worker.launchArguments
    app.launch()

    let orb = app.descendants(matching: .any)
    let elapsed = app.staticTexts["session.elapsed"]
    let tenSecondsIn = expectation(
      for: NSPredicate(format: "label MATCHES %@", "Elapsed 0:1[0-9]"), evaluatedWith: elapsed)
    await fulfillment(of: [tenSecondsIn], timeout: 30)
    XCTAssertTrue(orb["Your listener is listening"].exists)
    let prompt = app.staticTexts["session.prompt"]
    XCTAssertTrue(!prompt.exists || prompt.label.isEmpty)
    attach(app.screenshot(), named: "store-listening")

    let speaking = orb["Your listener is speaking"]
    XCTAssertTrue(speaking.waitForExistence(timeout: 420))
    attach(app.screenshot(), named: "store-speaking")

    let listening = orb["Your listener is listening"]
    let settled = expectation(
      for: NSPredicate { _, _ in listening.exists && prompt.exists && !prompt.label.isEmpty },
      evaluatedWith: nil)
    await fulfillment(of: [settled], timeout: 60)
    try? await Task.sleep(for: .seconds(2))
    attach(app.screenshot(), named: "store-prompt")

    // Two minutes of the fixture give the notes ideas and insights to show, not only open threads.
    let twoMinutesIn = expectation(
      for: NSPredicate(format: "label BEGINSWITH %@", "Elapsed 2:0"), evaluatedWith: elapsed)
    await fulfillment(of: [twoMinutesIn], timeout: 120)
    app.buttons["session.end"].tap()
    let notes = app.otherElements["notes.view"]
    XCTAssertTrue(notes.waitForExistence(timeout: 90))
    try? await Task.sleep(for: hold)
    attach(app.screenshot(), named: "store-notes")
  }
}
