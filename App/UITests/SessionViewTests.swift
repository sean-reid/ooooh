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
    app.launchArguments += ["-onboardingComplete", "1"] + Worker.launchArguments + arguments
    app.launch()

    let demo = app.buttons["home.demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15))
    demo.tap()

    let orb =
      app.otherElements["Your listener is listening"].firstMatch.exists
      ? app.otherElements["Your listener is listening"].firstMatch
      : app.images["Your listener is listening"].firstMatch
    XCTAssertTrue(orb.waitForExistence(timeout: 15))

    let elapsed = app.staticTexts["session.elapsed"]
    XCTAssertTrue(elapsed.waitForExistence(timeout: 15))
    let first = elapsed.label
    let advanced = expectation(
      for: NSPredicate(format: "label != %@", first), evaluatedWith: elapsed)
    wait(for: [advanced], timeout: 15)
    XCTAssertTrue(app.buttons["session.end"].exists)

    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    assertHaloFadesPastTheFrame(of: orb, in: screenshot.image, screen: app.frame)

    app.buttons["session.end"].tap()
    // How much the demo said before End depends on the runner, and whether a Worker answers on
    // the run, so End lands on one of three screens: nothing said, offline, or the notes.
    let empty = app.staticTexts["notes.empty"]
    let pending = app.otherElements["notes.pending"]
    let writing = app.staticTexts["notes.writing"]
    let written = app.otherElements["notes.view"]
    let landed = expectation(
      for: NSPredicate { _, _ in
        empty.exists || pending.exists || writing.exists || written.exists
      }, evaluatedWith: nil)
    wait(for: [landed], timeout: 15)
    if empty.exists {
      XCTAssertEqual(empty.label, "Nothing was said this time.")
      XCTAssertTrue(app.buttons["notes.done"].exists)
    } else if pending.exists {
      XCTAssertTrue(
        app.staticTexts["notes.pending.line"].label.hasPrefix("Your listener is offline."))
      XCTAssertTrue(app.buttons["notes.done"].exists)
    }

    let notes = XCTAttachment(screenshot: app.screenshot())
    notes.name = "\(name)-notes"
    notes.lifetime = .keepAlways
    add(notes)
  }

  /// Walks the row through the orb's center from 24 pt outside its frame to 24 pt inside. A halo
  /// that fades past the frame moves a level or so per pixel; one cut at the frame steps there.
  @MainActor
  private func assertHaloFadesPastTheFrame(of orb: XCUIElement, in image: UIImage, screen: CGRect) {
    guard let pixels = image.cgImage else { return XCTFail("the screenshot has no pixels") }
    let scale = CGFloat(pixels.width) / screen.width
    let frame = orb.frame
    let row = Int((frame.midY * scale).rounded())
    let from = Int(((frame.minX - 24) * scale).rounded())
    let to = Int(((frame.minX + 24) * scale).rounded())
    var data = [UInt8](repeating: 0, count: pixels.width * pixels.height * 4)
    let context = CGContext(
      data: &data, width: pixels.width, height: pixels.height, bitsPerComponent: 8,
      bytesPerRow: pixels.width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    context?.draw(pixels, in: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
    func brightness(_ x: Int) -> Int {
      let i = (row * pixels.width + x) * 4
      return Int(data[i]) + Int(data[i + 1]) + Int(data[i + 2])
    }
    let steps = (from..<to).map { abs(brightness($0 + 1) - brightness($0)) }
    XCTAssertLessThanOrEqual(
      steps.max() ?? 0, 3, "the halo steps \(steps.max() ?? 0) levels at the orb's left edge")
  }
}
