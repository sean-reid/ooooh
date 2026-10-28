import XCTest

/// Drives the demo at recorded pace for a screen recording: the first spoken line, End, the
/// notes. `OOOOH_DEMO_RECORDING` names the fixture to replay, and the test skips without it, so
/// CI never waits out a real session.
final class DemoRecordingTests: UITestCase {
  /// The first line can land anywhere in a fixture, so this wait spans one at recorded pace.
  let fixtureBudget: TimeInterval = 300

  @MainActor
  func testRecordsTheDemo() async throws {
    let fixture = ProcessInfo.processInfo.environment["OOOOH_DEMO_RECORDING"] ?? ""
    try XCTSkipIf(fixture.isEmpty, "OOOOH_DEMO_RECORDING names no fixture")
    try await requireWorker()
    let app = XCUIApplication()
    app.launchArguments +=
      [
        "-onboardingComplete", "1", "-reset-store", "1", "-demo", "1", "-demo-speed", "1",
        "-demo-fixture", fixture, "-ui-color-scheme", "dark",
      ] + Worker.launchArguments
    app.launch()

    XCTAssertTrue(app.staticTexts["session.elapsed"].appears())
    let prompt = app.staticTexts["session.prompt"]
    let spoken = expectation(for: NSPredicate(format: "label != ''"), evaluatedWith: prompt)
    XCTAssertEqual(XCTWaiter().wait(for: [spoken], timeout: fixtureBudget), .completed)
    try await Task.sleep(for: .seconds(5))
    app.buttons["session.end"].tap()

    let notes = app.otherElements["notes.view"]
    XCTAssertTrue(notes.appears())
    XCTAssertFalse(notes.staticTexts.firstMatch.label.isEmpty)
    try await Task.sleep(for: .seconds(8))
  }
}
