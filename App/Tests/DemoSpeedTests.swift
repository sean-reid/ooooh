import Foundation
import Testing

@testable import ooooh

@Suite struct DemoSpeedTests {
  func defaults(_ value: String?) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "DemoSpeedTests.\(UUID().uuidString)")!
    if let value { defaults.set(value, forKey: "demo-speed") }
    return defaults
  }

  @Test(arguments: [
    (nil, 1.0), ("16", 16.0), ("2.5", 2.5), ("0", 1.0), ("-4", 1.0), ("fast", 1.0),
    ("inf", Double.infinity),
  ])
  func readsTheLaunchArgument(value: String?, speed: Double) {
    #expect(DemoSpeed.read(defaults(value)) == speed)
  }
}
