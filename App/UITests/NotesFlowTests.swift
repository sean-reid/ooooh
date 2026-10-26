import XCTest

/// The demo at 16x against a running Worker: the fixture runs out, the wait, the real notes,
/// history, and the carryover card on the next launch. Skips when nothing answers at the Worker
/// URL.
final class NotesFlowTests: UITestCase {
  @MainActor
  func testDemoToNotesDark() async throws {
    try await runFlow(named: "flow-dark", arguments: ["-ui-color-scheme", "dark"])
  }

  @MainActor
  func testDemoToNotesLight() async throws {
    try await runFlow(named: "flow-light", arguments: ["-ui-color-scheme", "light"])
  }

  @MainActor
  func testDemoToNotesAccessibilityExtraLarge() async throws {
    try await runFlow(
      named: "flow-ax-xl",
      arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
  }

  @MainActor
  private func runFlow(named name: String, arguments: [String]) async throws {
    try await requireWorker()
    let app = XCUIApplication()
    let common = Worker.launchArguments + arguments
    app.launchArguments +=
      ["-onboardingComplete", "1", "-reset-store", "1", "-demo", "1", "-demo-speed", "16"]
      + common
    app.launch()

    XCTAssertTrue(app.staticTexts["session.elapsed"].appears())
    let writing = app.staticTexts["notes.writing"]
    XCTAssertTrue(writing.appears())
    XCTAssertEqual(writing.label, "writing your notes")
    attach(app, named: "\(name)-writing")

    let notes = app.otherElements["notes.view"]
    XCTAssertTrue(notes.appears())
    let title = notes.staticTexts.firstMatch.label
    XCTAssertFalse(title.isEmpty)
    let done = app.buttons["Done"].firstMatch
    waitUntilHittable(done)
    attach(app, named: "\(name)-notes")
    done.tap()

    let history = app.buttons["home.history"]
    waitUntilHittable(history)
    history.tap()
    let list = app.collectionViews["history.list"]
    waitUntilHittable(list)
    let row = list.buttons.containing(
      NSPredicate(format: "label BEGINSWITH %@", title + ",")
    ).firstMatch
    XCTAssertTrue(row.appears())
    attach(app, named: "\(name)-history")
    app.buttons["history.done"].tap()

    app.terminate()
    app.launchArguments = ["-onboardingComplete", "1"] + common
    app.launch()
    let card = app.otherElements["home.carryover"]
    XCTAssertTrue(card.appears())
    XCTAssertGreaterThan(card.buttons.count, 0)
    attach(app, named: "\(name)-carryover")
  }
}
