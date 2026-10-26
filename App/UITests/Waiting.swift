import XCTest

extension XCTestCase {
  /// CI runners animate sheets slowly; a tap during the transition is lost, so taps wait for this.
  @MainActor
  func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 15) {
    let hittable = expectation(
      for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
    XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: timeout), .completed)
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
