import XCTest

final class SessionViewTests: XCTestCase {
  @MainActor
  func testDemoSessionDark() {
    runDemo(named: "session-dark", arguments: ["-ui-color-scheme", "dark"])
  }

  @MainActor
  func testDemoSessionLight() {
    runDemo(named: "session-light", arguments: ["-ui-color-scheme", "light"])
  }

  @MainActor
  func testDemoSessionAccessibilityExtraLarge() {
    runDemo(
      named: "session-ax-xl",
      arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
  }

  @MainActor
  private func runDemo(named name: String, arguments: [String]) {
    let app = XCUIApplication()
    app.launchArguments += arguments
    app.launch()

    let demo = app.buttons["home.demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 5))
    demo.tap()

    let orb =
      app.otherElements["Your listener is listening"].firstMatch.exists
      ? app.otherElements["Your listener is listening"].firstMatch
      : app.images["Your listener is listening"].firstMatch
    XCTAssertTrue(orb.waitForExistence(timeout: 5))

    let elapsed = app.staticTexts["session.elapsed"]
    XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
    let first = elapsed.label
    let advanced = expectation(
      for: NSPredicate(format: "label != %@", first), evaluatedWith: elapsed)
    wait(for: [advanced], timeout: 5)
    XCTAssertTrue(app.buttons["session.end"].exists)

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)

    app.buttons["session.end"].tap()
    XCTAssertTrue(app.otherElements["notes.placeholder"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["notes.done"].exists)

    let notes = XCTAttachment(screenshot: app.screenshot())
    notes.name = "\(name)-notes"
    notes.lifetime = .keepAlways
    add(notes)
  }
}
