import XCTest

final class RecordViewTests: UITestCase {
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
    app.launchArguments += ["-onboardingComplete", "1"] + arguments
    app.launch()

    let open = app.buttons["Record a fixture"]
    waitUntilHittable(open)
    open.tap()

    XCTAssertTrue(app.buttons["record.start"].appears())
    XCTAssertEqual(app.staticTexts["record.elapsed"].label, "0:00")
    XCTAssertEqual(app.staticTexts["record.finals"].label, "0 final segments")
    XCTAssertTrue(app.buttons["Close"].exists)
    attach(app, named: name)
  }
}
