import XCTest

final class RecordViewTests: XCTestCase {
  @MainActor
  func testRecordViewDark() {
    captureRecordView(named: "record-dark", arguments: [])
  }

  @MainActor
  func testRecordViewLight() {
    captureRecordView(named: "record-light", arguments: ["-ui-color-scheme", "light"])
  }

  @MainActor
  func testRecordViewAccessibilityExtraLarge() {
    captureRecordView(
      named: "record-ax-xl",
      arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
  }

  @MainActor
  private func captureRecordView(named name: String, arguments: [String]) {
    let app = XCUIApplication()
    app.launchArguments += arguments
    app.launch()

    let open = app.buttons["Record a fixture"]
    XCTAssertTrue(open.waitForExistence(timeout: 5))
    open.tap()

    XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["record.elapsed"].label, "0:00")
    XCTAssertEqual(app.staticTexts["record.finals"].label, "0 final segments")
    XCTAssertTrue(app.buttons["Close"].exists)

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
