import Foundation
import Testing

@testable import ooooh

@Suite struct DemoFixtureTests {
  func defaults(_ value: String?) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "DemoFixtureTests.\(UUID().uuidString)")!
    if let value { defaults.set(value, forKey: "demo-fixture") }
    return defaults
  }

  func file(_ contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
    try Data(contents.utf8).write(to: url)
    return url
  }

  @Test func aFixtureFileOnTheCommandLineWins() throws {
    let url = try file(#"{"segments":[{"text":"hi","start":0,"end":1,"isFinal":true}]}"#)
    #expect(DemoFixture.url(defaults(url.path)) == url)
  }

  @Test func unsetIsTheBundledFixture() throws {
    #expect(DemoFixture.url(defaults(nil)) == (try DebugHistory.demoFixtureURL()))
  }

  @Test func anEmptyMissingOrMalformedPathIsTheBundledFixture() throws {
    let bundled = try DebugHistory.demoFixtureURL()
    #expect(DemoFixture.url(defaults("")) == bundled)
    #expect(DemoFixture.url(defaults("/nowhere/\(UUID().uuidString).json")) == bundled)
    #expect(DemoFixture.url(defaults(try file(#"{"segments":"no"}"#).path)) == bundled)
  }
}
