import XCTest

/// Drives the demo at recorded pace for a screen recording: the first spoken line, End, the
/// notes. `OOOOH_DEMO_RECORDING` names the fixture to replay, and the test skips without it, so
/// CI never waits out a real session.
final class DemoRecordingTests: UITestCase {
  /// The first line can land anywhere in a fixture, so this wait spans one at recorded pace.
  let fixtureBudget: TimeInterval = 300

  @MainActor
  func testRecordsTheDemo() async throws {
    let app = try await launchDemo()

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

  /// The reel: the session until two lines have landed or the fixture is nearly out, End, the
  /// notes read and edited, history, and the carryover card back on the home screen.
  /// Every step logs a `reel` marker with the wall clock, so the recording can be cut against them.
  @MainActor
  func testRecordsTheReel() async throws {
    let app = try await launchDemo(arguments: ["-hide-debug", "1"])

    XCTAssertTrue(app.staticTexts["session.elapsed"].appears())
    mark("session started")
    let prompt = app.staticTexts["session.prompt"]
    var lines: [String] = []
    let started = Date.now
    while Date.now.timeIntervalSince(started) < 238, lines.count < 2,
      app.buttons["session.end"].exists
    {
      let label = prompt.label
      if !label.isEmpty, label != lines.last {
        lines.append(label)
        mark("line \(label)")
      }
      try await Task.sleep(for: .milliseconds(250))
    }
    XCTAssertFalse(lines.isEmpty)
    try await Task.sleep(for: .seconds(5))
    if app.buttons["session.end"].exists {
      app.buttons["session.end"].tap()
      mark("end tapped")
    }

    let notes = app.otherElements["notes.view"]
    XCTAssertTrue(notes.appears())
    mark("notes shown")
    try await Task.sleep(for: .seconds(5))

    let toggle = app.buttons["transcript.toggle"]
    swipeUp(app, until: toggle)
    toggle.tap()
    mark("transcript expanded")
    try await Task.sleep(for: .seconds(2))
    let line = notes.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH 'transcript.line.'")
    ).firstMatch
    swipeUp(app, until: line)
    line.press(forDuration: 1)
    mark("line marked bad")
    XCTAssertTrue(notes.staticTexts["Marked bad"].appears())
    try await Task.sleep(for: .seconds(2.5))

    for _ in 0..<6 { app.swipeDown() }
    app.buttons["notes.edit"].tap()
    mark("editing")
    try await Task.sleep(for: .seconds(2))
    let deletes = notes.buttons.matching(NSPredicate(format: "label == 'Delete'"))
    let before = deletes.count
    deletes.firstMatch.tap()
    mark("item deleted")
    wait(until: { deletes.count < before }, "the item stayed after Delete")
    try await Task.sleep(for: .seconds(2))
    let resolves = notes.descendants(matching: .any).matching(
      NSPredicate(format: "label == 'Resolved'"))
    if resolves.count > 1 {
      swipeUp(app, until: resolves.firstMatch)
      resolves.firstMatch.tap()
      mark("thread resolved")
      try await Task.sleep(for: .seconds(2))
    }
    app.buttons["notes.editing.done"].tap()
    mark("editing done")
    try await Task.sleep(for: .seconds(3))

    app.buttons["notes.done"].tap()
    mark("notes done")
    let card = app.otherElements["home.carryover"]
    XCTAssertTrue(card.appears())
    try await Task.sleep(for: .seconds(2.5))
    app.buttons["home.history"].tap()
    mark("history opened")
    let list = app.collectionViews["history.list"]
    waitUntilHittable(list)
    XCTAssertTrue(list.buttons.firstMatch.appears())
    try await Task.sleep(for: .seconds(3.5))
    app.buttons["history.done"].tap()
    mark("history closed")
    waitUntilHittable(card)
    try await Task.sleep(for: .seconds(4))
  }

  @MainActor
  private func launchDemo(arguments: [String] = []) async throws -> XCUIApplication {
    let fixture = ProcessInfo.processInfo.environment["OOOOH_DEMO_RECORDING"] ?? ""
    try XCTSkipIf(fixture.isEmpty, "OOOOH_DEMO_RECORDING names no fixture")
    try await requireWorker()
    let app = XCUIApplication()
    app.launchArguments +=
      [
        "-onboardingComplete", "1", "-reset-store", "1", "-demo", "1", "-demo-speed", "1",
        "-demo-fixture", fixture, "-ui-color-scheme", "dark",
      ] + arguments + Worker.launchArguments
    app.launch()
    return app
  }

  private func mark(_ event: String) {
    NSLog("reel \(event)")
  }

  /// The notes scroll a long way at recorded pace, so this swipes further than the shared helper.
  @MainActor
  private func swipeUp(_ app: XCUIApplication, until element: XCUIElement) {
    for _ in 0..<10 where !element.isHittable {
      app.swipeUp()
    }
    waitUntilHittable(element)
  }
}
