import XCTest

/// The demo against a running Worker: End, the wait, the real notes, history, and the carryover
/// card on the next launch. Skips when nothing answers at the Worker URL.
final class NotesFlowTests: XCTestCase {
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
    app.launchArguments += ["-onboardingComplete", "1", "-reset-store", "1", "-demo", "1"] + common
    app.launch()

    let elapsed = app.staticTexts["session.elapsed"]
    XCTAssertTrue(elapsed.waitForExistence(timeout: 15))
    let aMinuteIn = expectation(
      for: NSPredicate(format: "label BEGINSWITH %@", "Elapsed 1:0"), evaluatedWith: elapsed)
    await fulfillment(of: [aMinuteIn], timeout: 90)
    app.buttons["session.end"].tap()

    let writing = app.staticTexts["notes.writing"]
    XCTAssertTrue(writing.waitForExistence(timeout: 15))
    XCTAssertEqual(writing.label, "writing your notes")
    attach(app.screenshot(), named: "\(name)-writing")

    let notes = app.otherElements["notes.view"]
    XCTAssertTrue(notes.waitForExistence(timeout: 90))
    let title = notes.staticTexts.firstMatch.label
    XCTAssertFalse(title.isEmpty)
    try? await Task.sleep(for: .seconds(1))
    attach(app.screenshot(), named: "\(name)-notes")
    app.buttons["Done"].firstMatch.tap()

    let history = app.buttons["home.history"]
    let historyReady = expectation(
      for: NSPredicate(format: "isHittable == true"), evaluatedWith: history)
    await fulfillment(of: [historyReady], timeout: 15)
    history.tap()
    let list = app.collectionViews["history.list"]
    let listReady = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: list)
    await fulfillment(of: [listReady], timeout: 15)
    let row = list.buttons.containing(
      NSPredicate(format: "label BEGINSWITH %@", title + ",")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 15))
    attach(app.screenshot(), named: "\(name)-history")
    app.buttons["history.done"].tap()

    app.terminate()
    app.launchArguments = ["-onboardingComplete", "1"] + common
    app.launch()
    let card = app.otherElements["home.carryover"]
    XCTAssertTrue(card.waitForExistence(timeout: 15))
    XCTAssertGreaterThan(card.buttons.count, 0)
    attach(app.screenshot(), named: "\(name)-carryover")
  }
}
