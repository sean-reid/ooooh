import XCTest

/// History and the carryover card over a seeded store, so they run without the Worker.
final class HistoryTests: XCTestCase {
  /// CI runners animate sheets slowly; every wait in this file gets the same room.
  private let wait: TimeInterval = 15

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
      arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"],
      searchesAndDeletes: false)
  }

  /// Search and swipe-to-delete run at the two regular sizes; the accessibility run checks the
  /// screens, since the tall rows make the keyboard and the swipe unreliable on the CI simulator.
  @MainActor
  private func runHistory(named name: String, arguments: [String], searchesAndDeletes: Bool = true)
  {
    let app = XCUIApplication()
    app.launchArguments +=
      ["-onboardingComplete", "1", "-reset-store", "1", "-seed-history", "1"] + arguments
    app.launch()

    let card = app.otherElements["home.carryover"]
    XCTAssertTrue(card.waitForExistence(timeout: wait))
    XCTAssertTrue(card.buttons["Pick up How Sam and I weight time against money"].exists)
    XCTAssertTrue(card.buttons["Pick up Whether the eighteen month lease is a problem"].exists)
    attach(app.screenshot(), named: "\(name)-carryover")
    app.swipeUp()
    attach(app.screenshot(), named: "\(name)-carryover-scrolled")
    XCTAssertTrue(card.buttons["Pick up Whether the eighteen month lease is a problem"].isHittable)
    app.swipeDown()

    let history = app.buttons["home.history"]
    waitUntilHittable(history)
    history.tap()
    let list = app.collectionViews["history.list"]
    waitUntilHittable(list)
    let row = list.buttons.containing(
      NSPredicate(format: "label BEGINSWITH %@", "Carver Street or the park,")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: wait))
    XCTAssertTrue(row.label.contains("2 open threads"))
    attach(app.screenshot(), named: "\(name)-history")

    row.tap()
    let notes = app.otherElements["notes.view"]
    XCTAssertTrue(notes.waitForExistence(timeout: wait))
    XCTAssertTrue(notes.staticTexts["Carver Street or the park"].exists)
    XCTAssertTrue(notes.staticTexts["Open threads"].exists)
    attach(app.screenshot(), named: "\(name)-stored-notes")
    app.buttons["notes.done"].tap()
    waitUntilHittable(list)

    if searchesAndDeletes {
      let search = app.textFields["history.search"]
      focus(search)
      search.typeText("eighteen month")
      XCTAssertTrue(row.waitForExistence(timeout: wait))
      search.typeText(" zebra")
      XCTAssertTrue(app.staticTexts["history.empty"].waitForExistence(timeout: wait))
      app.buttons["Clear the search"].tap()
      XCTAssertTrue(row.waitForExistence(timeout: wait))

      row.swipeLeft()
      let delete = app.buttons["Delete"]
      XCTAssertTrue(delete.waitForExistence(timeout: wait))
      delete.tap()
      XCTAssertTrue(app.staticTexts["history.empty"].waitForExistence(timeout: wait))
    }
    app.buttons["history.done"].tap()
    waitUntilHittable(history)
    XCTAssertEqual(card.exists, !searchesAndDeletes)
  }

  /// Taps until the field has keyboard focus, since a tap during a sheet transition is lost.
  @MainActor
  private func focus(_ field: XCUIElement) {
    for _ in 0..<3 {
      field.tap()
      let focused = expectation(
        for: NSPredicate { _, _ in (field.value(forKey: "hasKeyboardFocus") as? Bool) == true },
        evaluatedWith: nil)
      if XCTWaiter().wait(for: [focused], timeout: 3) == .completed { return }
    }
    XCTFail("the search field never took keyboard focus")
  }
}
