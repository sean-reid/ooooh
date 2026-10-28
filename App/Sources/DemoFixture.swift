#if DEBUG
  import Foundation
  import Transcription

  /// `-demo-fixture /path/to/file.json` replays that fixture in place of the bundled decision
  /// fixture. Unset, or a path that does not decode as a fixture, is the bundled one.
  enum DemoFixture {
    static func url(_ defaults: UserDefaults = .standard) -> URL? {
      if let path = defaults.string(forKey: "demo-fixture"), !path.isEmpty {
        let url = URL(filePath: path)
        if let data = try? Data(contentsOf: url),
          (try? JSONDecoder().decode(FixtureTranscriber.Fixture.self, from: data)) != nil
        {
          return url
        }
      }
      return try? DebugHistory.demoFixtureURL()
    }
  }
#endif
