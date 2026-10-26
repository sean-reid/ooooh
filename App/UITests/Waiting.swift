import XCTest

/// Every wait in the suite shares this budget. A CI simulator is slow, not broken, so a wait
/// ends when its condition holds and fails only past this.
let waitBudget: TimeInterval = 120

extension XCUIElement {
  /// True once the element exists, within the shared budget.
  func appears() -> Bool { waitForExistence(timeout: waitBudget) }

  /// True once the element is gone, within the shared budget.
  func disappears() -> Bool { waitForNonExistence(timeout: waitBudget) }
}

extension XCTestCase {
  /// Waits until `condition` holds, within the shared budget.
  @MainActor
  func wait(
    until condition: @escaping () -> Bool, _ message: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let met = expectation(for: NSPredicate { _, _ in condition() }, evaluatedWith: nil)
    if XCTWaiter().wait(for: [met], timeout: waitBudget) != .completed {
      XCTFail(message, file: file, line: line)
    }
  }

  /// Sheets and scrolls animate, and a tap during the transition is lost, so taps wait for this.
  @MainActor
  func waitUntilHittable(
    _ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line
  ) {
    wait(
      until: { element.isHittable }, "not hittable within \(waitBudget) s: \(element)",
      file: file, line: line)
  }

  /// Swipes up until the element can be tapped, for rows below the fold at large type.
  @MainActor
  func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<4 where !element.isHittable {
      app.swipeUp()
    }
    waitUntilHittable(element)
  }
}
