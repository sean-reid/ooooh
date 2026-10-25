import Testing

@testable import Design

@Suite struct DesignTests {
  @Test func everyPhaseNamesTheListener() {
    let labels = Set(OrbPhase.allCases.map(\.accessibilityLabel))
    #expect(labels.count == OrbPhase.allCases.count)
    #expect(labels.allSatisfy { $0.hasPrefix("Your listener") })
    #expect(OrbPhase.resting.accessibilityLabel == "Your listener, resting")
  }

  @Test func bundlesBothFacesAndTheLicense() throws {
    for face in Typography.Face.allCases {
      #expect(face.url != nil, "\(face.rawValue).ttf missing from the Fonts resource")
    }
    let license = try #require(Typography.licenseURL)
    let text = try String(contentsOf: license, encoding: .utf8)
    #expect(text.contains("SIL Open Font License, Version 1.1"))
  }

  @Test func registersFontsOnce() {
    #expect(Typography.registerFonts())
    #expect(Typography.registerFonts())
  }

  @Test func stillFrameTakesThePhaseLook() {
    let frame = OrbMotion.still(at: 3, level: 1.4, phase: .offline)
    #expect(frame.clock == 3)
    #expect(frame.breath == 1)
    #expect(frame.pose.dim == 1)
    #expect(frame.pose.speed == 0)
  }

  @Test func blobStaysClosedAndNearItsRadius() {
    let path = OrbGeometry.blob(
      center: .init(x: 100, y: 100), radius: 50, clock: 2.5, drift: 1, breath: 1, stretch: 1.18)
    let box = path.boundingRect
    #expect(box.width > 70 && box.width < 110)
    #expect(box.height > 85 && box.height < 125)
    #expect(path.contains(.init(x: 100, y: 100)))
  }
}
