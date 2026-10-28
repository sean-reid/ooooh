import XCTest

/// The moments the store screenshots need, with the Demo row hidden, each held three seconds so
/// a screen recording of the run has a shot to cut. The session test runs the demo against a
/// Worker, tools/store/worker.mjs or a real one, and skips when nothing answers at its URL.
final class StoreCaptureTests: UITestCase {
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
    XCTAssertTrue(card.appears())
    XCTAssertFalse(app.buttons["home.demo"].exists)
    try? await Task.sleep(for: hold)
    attach(app, named: "store-carryover")
  }

  @MainActor
  func testOnboardingQuietMode() async {
    let app = XCUIApplication()
    app.launchArguments += common + ["-onboarding", "1"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Think out loud."].appears())
    try? await Task.sleep(for: hold)
    app.swipeLeft()
    XCTAssertTrue(app.staticTexts["It waits."].appears())
    try? await Task.sleep(for: hold)
    attach(app, named: "store-quiet")
  }

  @MainActor
  func testSettingsDataControls() async {
    let app = XCUIApplication()
    app.launchArguments += common + ["-seed-history", "1"]
    app.launch()
    let settings = app.buttons["home.settings"]
    waitUntilHittable(settings)
    settings.tap()
    XCTAssertTrue(app.buttons["settings.done"].appears())
    XCTAssertTrue(app.buttons["settings.deleteAll"].exists)
    try? await Task.sleep(for: hold)
    attach(app, named: "store-settings")
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
    let listening = orb["Your listener is listening"]
    let prompt = app.staticTexts["session.prompt"]
    wait(
      until: { listening.exists && (!prompt.exists || prompt.label.isEmpty) },
      "the session never settled into listening")
    try? await Task.sleep(for: hold)
    attach(app, named: "store-listening")
    try auditAccessibility(app, named: "store-listening")

    let speaking = orb["Your listener is speaking"]
    // A real Jev may ask anywhere in the 410 s fixture.
    XCTAssertTrue(speaking.waitForExistence(timeout: 420))
    attach(app, named: "store-speaking")
    try auditAccessibility(app, named: "store-speaking")

    wait(
      until: { listening.exists && prompt.exists && !prompt.label.isEmpty },
      "the question never stayed beside the listening orb")
    try? await Task.sleep(for: hold)
    attach(app, named: "store-prompt")
    try auditAccessibility(app, named: "store-prompt")

    // The seeded notes quote utterance 9, which ends at 2:16, so End waits for 2:20.
    let elapsed = app.staticTexts["session.elapsed"]
    wait(until: { elapsed.label.hasPrefix("Elapsed 2:2") }, "the session never reached 2:20")
    app.buttons["session.end"].tap()
    XCTAssertTrue(app.otherElements["notes.view"].appears())
    try? await Task.sleep(for: hold)
    attach(app, named: "store-notes")
  }
}
