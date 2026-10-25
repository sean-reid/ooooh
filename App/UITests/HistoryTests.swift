import XCTest

/// History and the carryover card over a seeded store, so they run without the Worker.
final class HistoryTests: XCTestCase {
  @MainActor
  func testHistoryDark() {
    runHistory(named: "history-dark", arguments: ["-ui-color-scheme", "dark"])
  }

  @MainActor
  func testHistoryLight() {
    runHistory(named: "history-light", arguments: ["-ui-color-scheme", "light"])
  }

  @MainActor
  func testHistoryAccessibilityExtraLarge() {
    runHistory(
      named: "history-ax-xl",
      arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
  }

  @MainActor
  private func runHistory(named name: String, arguments: [String]) {
    let app = XCUIApplication()
    app.launchArguments +=
      ["-onboardingComplete", "1", "-reset-store", "1", "-seed-history", "1"] + arguments
    app.launch()

    let card = app.otherElements["home.carryover"]
    XCTAssertTrue(card.waitForExistence(timeout: 10))
    XCTAssertTrue(card.buttons["Pick up How Sam and I weight time against money"].exists)
    XCTAssertTrue(card.buttons["Pick up Whether the eighteen month lease is a problem"].exists)
    attach(app.screenshot(), named: "\(name)-carryover")

    app.buttons["home.history"].tap()
    let list = app.collectionViews["history.list"]
    XCTAssertTrue(list.waitForExistence(timeout: 5))
    let row = list.buttons.containing(
      NSPredicate(format: "label BEGINSWITH %@", "Carver Street or the park,")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    XCTAssertTrue(row.label.contains("2 open threads"))
    attach(app.screenshot(), named: "\(name)-history")

    row.tap()
    let notes = app.otherElements["notes.view"]
    XCTAssertTrue(notes.waitForExistence(timeout: 5))
    XCTAssertTrue(notes.staticTexts["Carver Street or the park"].exists)
    XCTAssertTrue(notes.staticTexts["Open threads"].exists)
    attach(app.screenshot(), named: "\(name)-stored-notes")
    app.buttons["Done"].firstMatch.tap()
    XCTAssertTrue(list.waitForExistence(timeout: 5))

    let search = app.textFields["history.search"]
    search.tap()
    search.typeText("eighteen month")
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    search.typeText(" zebra")
    XCTAssertTrue(app.staticTexts["history.empty"].waitForExistence(timeout: 5))
    app.buttons["Clear the search"].tap()
    XCTAssertTrue(row.waitForExistence(timeout: 5))

    row.swipeLeft()
    app.buttons["Delete"].tap()
    XCTAssertTrue(app.staticTexts["history.empty"].waitForExistence(timeout: 5))
    app.buttons["history.done"].tap()
    XCTAssertFalse(card.waitForExistence(timeout: 2))
  }

  private func attach(_ screenshot: XCUIScreenshot, named name: String) {
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
