import XCTest

final class SessionViewTests: UITestCase {
  @MainActor
  func testDemoSessionDark() throws {
    try runDemo(named: "session-dark", arguments: ["-ui-color-scheme", "dark"])
  }

  @MainActor
  func testDemoSessionLight() throws {
    try runDemo(named: "session-light", arguments: ["-ui-color-scheme", "light"])
  }

  @MainActor
  func testDemoSessionAccessibilityExtraLarge() throws {
    try runDemo(
      named: "session-ax-xl",
      arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
  }

  /// A Worker at a closed port fails every request at once, so the session goes offline within
  /// seconds, and End lands on the notes screen that says so.
  @MainActor
  func testOfflineSession() throws {
    let app = XCUIApplication()
    app.launchArguments +=
      ["-onboardingComplete", "1", "-reset-store", "1", "-demo-speed", "16"]
      + ["-worker-url", "http://127.0.0.1:1"]
    app.launch()

    let demo = app.buttons["home.demo"]
    waitUntilHittable(demo)
    demo.tap()

    let offline = app.staticTexts["session.offline"]
    XCTAssertTrue(offline.appears())
    XCTAssertEqual(offline.label, "listening only, your listener is offline")
    XCTAssertTrue(app.descendants(matching: .any)["Your listener is offline"].firstMatch.exists)
    attach(app, named: "session-offline")
    try auditAccessibility(app, named: "session-offline")

    app.buttons["session.end"].tap()
    XCTAssertTrue(app.otherElements["notes.pending"].appears())
    XCTAssertTrue(
      app.staticTexts["notes.pending.line"].label.hasPrefix("Your listener is offline."))
    attach(app, named: "notes-offline")
    try auditAccessibility(app, named: "notes-offline")
  }

  /// At a hundredth of the recorded pace nothing is final before End, so End lands on the
  /// screen for a session with nothing said.
  @MainActor
  func testEndBeforeAnythingIsSaid() throws {
    let app = XCUIApplication()
    app.launchArguments +=
      ["-onboardingComplete", "1", "-reset-store", "1", "-demo-speed", "0.01"]
      + Worker.launchArguments
    app.launch()

    let demo = app.buttons["home.demo"]
    waitUntilHittable(demo)
    demo.tap()

    let end = app.buttons["session.end"]
    waitUntilHittable(end)
    end.tap()
    let empty = app.staticTexts["notes.empty"]
    XCTAssertTrue(empty.appears())
    XCTAssertEqual(empty.label, "Nothing was said this time.")
    attach(app, named: "notes-empty")
    try auditAccessibility(app, named: "notes-empty")
    app.buttons["notes.done"].tap()
    waitUntilHittable(app.buttons["home.start"])
  }

  @MainActor
  private func runDemo(named name: String, arguments: [String]) throws {
    let app = XCUIApplication()
    app.launchArguments +=
      ["-onboardingComplete", "1", "-reset-store", "1"] + Worker.launchArguments + arguments
    app.launch()

    let demo = app.buttons["home.demo"]
    waitUntilHittable(demo)
    demo.tap()

    let orb = app.descendants(matching: .any)["Your listener is listening"].firstMatch
    XCTAssertTrue(orb.appears())
    let elapsed = app.staticTexts["session.elapsed"]
    XCTAssertTrue(elapsed.appears())
    let first = elapsed.label
    wait(until: { elapsed.label != first }, "the session clock never moved past \(first)")
    XCTAssertTrue(app.buttons["session.end"].exists)

    if let image = attach(app, named: name) {
      assertHaloFadesPastTheFrame(of: orb, in: image, screen: app.frame)
    }
    try auditAccessibility(app, named: name)

    app.buttons["session.end"].tap()
    // How much the demo said before End depends on the runner, and whether a Worker answers on
    // the run, so End lands on one of three screens: nothing said, offline, or the notes.
    let empty = app.staticTexts["notes.empty"]
    let pending = app.otherElements["notes.pending"]
    let writing = app.staticTexts["notes.writing"]
    let written = app.otherElements["notes.view"]
    wait(
      until: { empty.exists || pending.exists || writing.exists || written.exists },
      "End landed on no notes screen")
    if empty.exists {
      XCTAssertEqual(empty.label, "Nothing was said this time.")
      XCTAssertTrue(app.buttons["notes.done"].exists)
    } else if pending.exists {
      XCTAssertTrue(
        app.staticTexts["notes.pending.line"].label.hasPrefix("Your listener is offline."))
      XCTAssertTrue(app.buttons["notes.done"].exists)
    }
    attach(app, named: "\(name)-notes")
    try auditAccessibility(app, named: "\(name)-notes")
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
