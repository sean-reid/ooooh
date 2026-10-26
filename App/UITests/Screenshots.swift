import XCTest

/// Screenshots are artifacts of the run, not assertions: one the simulator does not deliver in
/// time is logged and the test goes on.
class UITestCase: XCTestCase {
  /// Keeps a screenshot of the app in the result bundle under `name`. Returns the image, or nil
  /// when the simulator delivered none.
  @MainActor
  @discardableResult
  func attach(_ app: XCUIApplication, named name: String) -> UIImage? {
    let screenshot = app.screenshot()
    guard screenshot.image.cgImage != nil else {
      print("no screenshot for \(name)")
      return nil
    }
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    return screenshot.image
  }

  override func record(_ issue: XCTIssue) {
    if issue.compactDescription.contains("Failed to get screenshot") {
      print(issue.compactDescription)
      return
    }
    super.record(issue)
  }
}

final class ScreenshotsTests: UITestCase {
  func testAScreenshotTheSimulatorNeverDeliveredIsNotAFailure() {
    record(
      XCTIssue(
        type: .system,
        compactDescription: "Failed to get screenshot: Timed out while requesting screenshot"))
  }

  func testOtherIssuesStillFail() {
    XCTExpectFailure("a real failure keeps failing") {
      record(XCTIssue(type: .assertionFailure, compactDescription: "something else"))
    }
  }
}
