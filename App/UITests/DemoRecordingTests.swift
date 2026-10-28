import XCTest

/// Drives the demo at recorded pace for a screen recording: the first spoken line, End, the
/// notes. `OOOOH_DEMO_RECORDING` names the fixture to replay, and the test skips without it, so
/// CI never waits out a real session.
final class DemoRecordingTests: UITestCase {
  /// The first line can land anywhere in a fixture, so this wait spans one at recorded pace.
  let fixtureBudget: TimeInterval = 300
  /// The reel taps End once the clock reaches this: a pause late in the fixture, before it runs out.
  let endSeconds: TimeInterval = 228

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

  /// The reel: the session until `endSeconds`, End, the notes read and edited, history, and the
  /// carryover card back on the home screen.
  /// Every step logs a `reel` marker with the wall clock, so the recording can be cut against them.
  @MainActor
  func testRecordsTheReel() async throws {
    let app = try await launchDemo(arguments: ["-hide-debug", "1"])

    let elapsed = app.staticTexts["session.elapsed"]
    XCTAssertTrue(elapsed.appears())
    mark("session started")
    let prompt = app.staticTexts["session.prompt"]
    var lines: [String] = []
    while app.buttons["session.end"].exists, Self.seconds(in: elapsed.label) < endSeconds {
      let label = prompt.label
      if !label.isEmpty, label != lines.last {
        lines.append(label)
        mark("line \(label)")
      }
      try await Task.sleep(for: .milliseconds(250))
    }
    XCTAssertFalse(lines.isEmpty)
    if app.buttons["session.end"].exists {
      app.buttons["session.end"].tap()
      mark("end tapped")
    }

    let notes = app.otherElements["notes.view"]
    XCTAssertTrue(notes.appears())
    mark("notes shown")
    try await Task.sleep(for: .seconds(4))

    try await scroll(app, until: notes.staticTexts["Open threads"])
    try await Task.sleep(for: .seconds(2))
    let toggle = app.buttons["transcript.toggle"]
    try await scroll(app, until: toggle)
    try await Task.sleep(for: .seconds(1))
    toggle.tap()
    mark("transcript expanded")
    try await Task.sleep(for: .seconds(2))
    let line = notes.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH 'transcript.line.'")
    ).firstMatch
    try await scroll(app, until: line)
    try await Task.sleep(for: .seconds(1))
    line.press(forDuration: 1)
    mark("line marked bad")
    XCTAssertTrue(notes.staticTexts["Marked bad"].appears())
    try await Task.sleep(for: .seconds(2))

    for _ in 0..<8 { app.swipeDown() }
    try await Task.sleep(for: .seconds(1))
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
      try await scroll(app, until: resolves.firstMatch)
      try await Task.sleep(for: .seconds(1))
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

  /// Seconds in the clock's label, "Elapsed 3:48".
  static func seconds(in label: String) -> TimeInterval {
    let parts = (label.split(separator: " ").last ?? "").split(separator: ":").compactMap { Double($0) }
    return parts.count == 2 ? parts[0] * 60 + parts[1] : 0
  }

  /// Scrolls the notes a screen at a time, two seconds a screen, holding at each stop until the
  /// element can be tapped.
  @MainActor
  private func scroll(_ app: XCUIApplication, until element: XCUIElement) async throws {
    for _ in 0..<10 where !element.isHittable {
      let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
      let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
      from.press(forDuration: 0.1, thenDragTo: to, withVelocity: 330, thenHoldForDuration: 0.3)
      try await Task.sleep(for: .seconds(1.5))
    }
    waitUntilHittable(element)
  }
}
