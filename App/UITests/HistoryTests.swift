import XCTest

/// History and the carryover card over a seeded store, so they run without the Worker.
final class HistoryTests: UITestCase {
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
    XCTAssertTrue(card.appears())
    let lease = card.buttons["Pick up Whether the eighteen month lease is a problem"]
    XCTAssertTrue(card.buttons["Pick up How Sam and I weight time against money"].exists)
    XCTAssertTrue(lease.exists)
    attach(app, named: "\(name)-carryover")
    app.swipeUp()
    attach(app, named: "\(name)-carryover-scrolled")
    waitUntilHittable(lease)
    app.swipeDown()

    let history = app.buttons["home.history"]
    waitUntilHittable(history)
    history.tap()
    let list = app.collectionViews["history.list"]
    waitUntilHittable(list)
    let row = list.buttons.containing(
      NSPredicate(format: "label BEGINSWITH %@", "Carver Street or the park,")
    ).firstMatch
    XCTAssertTrue(row.appears())
    XCTAssertTrue(row.label.contains("2 open threads"))
    attach(app, named: "\(name)-history")

    row.tap()
    let notes = app.otherElements["notes.view"]
    XCTAssertTrue(notes.appears())
    XCTAssertTrue(notes.staticTexts["Carver Street or the park"].exists)
    XCTAssertTrue(notes.staticTexts["Open threads"].exists)
    attach(app, named: "\(name)-stored-notes")
    if searchesAndDeletes {
      editNotes(notes, in: app, named: name)
    }
    app.buttons["notes.done"].tap()
    waitUntilHittable(list)
    if searchesAndDeletes {
      XCTAssertTrue(row.appears())
      XCTAssertTrue(row.label.contains("1 open thread"))
    }

    if searchesAndDeletes {
      let search = app.textFields["history.search"]
      waitUntilHittable(search)
      search.tap()
      wait(
        until: { (search.value(forKey: "hasKeyboardFocus") as? Bool) == true },
        "the search field never took keyboard focus")
      search.typeText("eighteen month")
      XCTAssertTrue(row.appears())
      search.typeText(" zebra")
      XCTAssertTrue(app.staticTexts["history.empty"].appears())
      app.buttons["Clear the search"].tap()
      XCTAssertTrue(row.appears())

      row.swipeLeft()
      let delete = app.buttons["Delete"]
      XCTAssertTrue(delete.appears())
      delete.tap()
      XCTAssertTrue(app.staticTexts["history.empty"].appears())
    }
    app.buttons["history.done"].tap()
    waitUntilHittable(history)
    XCTAssertTrue(searchesAndDeletes ? card.disappears() : card.appears())
  }

  /// Edit, resolve the first thread, tap the decision, type onto its end, Done: the thread
  /// reads as resolved and the new text shows. The resolve comes first, before the keyboard
  /// covers the thread rows. Both taps scroll their row into view on their own, so they wait
  /// for existence, not hittability.
  @MainActor
  private func editNotes(_ notes: XCUIElement, in app: XCUIApplication, named name: String) {
    let decision = "Make the case for the park place tonight with the numbers"
    app.buttons["notes.edit"].tap()
    let resolved = notes.descendants(matching: .any).matching(
      NSPredicate(format: "label == 'Resolved'")
    ).firstMatch
    XCTAssertTrue(resolved.appears())
    resolved.tap()
    let text = notes.buttons[decision]
    XCTAssertTrue(text.appears())
    text.tap()
    let field = notes.descendants(matching: .any)["notes.field"]
    XCTAssertTrue(field.appears())
    wait(
      until: { (field.value(forKey: "hasKeyboardFocus") as? Bool) == true },
      "the note field never took keyboard focus")
    field.typeText(", with the commute times")
    attach(app, named: "\(name)-editing-notes")
    app.buttons["notes.editing.done"].tap()

    let edited = notes.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", decision + ", with the commute times")
    ).firstMatch
    XCTAssertTrue(edited.appears())
    let thread = notes.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "How Sam and I weight time against money, resolved")
    ).firstMatch
    XCTAssertTrue(thread.exists)
    attach(app, named: "\(name)-edited-notes")
  }
}
