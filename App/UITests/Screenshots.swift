import XCTest

extension XCTestCase {
  /// Keeps a screenshot in the result bundle under `name`.
  func attach(_ screenshot: XCUIScreenshot, named name: String) {
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
