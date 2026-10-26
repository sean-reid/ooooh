import Foundation

/// Replays a recorded session's segments on a scaled clock, so the pipeline runs with no microphone.
public struct FixtureTranscriber: Transcriber {
  public struct Fixture: Codable, Sendable {
    public var segments: [Segment]
    public init(segments: [Segment]) { self.segments = segments }
  }

  let fixture: Fixture
  let speed: Double
  let replay = ReplayTask()

  public init(fixture: Fixture, speed: Double = .infinity) {
    self.fixture = fixture
    self.speed = speed
  }

  public init(contentsOf url: URL, speed: Double = .infinity) throws {
    let data = try Data(contentsOf: url)
    self.init(fixture: try JSONDecoder().decode(Fixture.self, from: data), speed: speed)
  }

  public func events() -> AsyncStream<TranscriptEvent> {
    AsyncStream { continuation in
      let task = Task {
        var clock: TimeInterval = 0
        for segment in fixture.segments {
          if speed.isFinite, segment.start > clock {
            try? await Task.sleep(for: .seconds((segment.start - clock) / speed))
          }
          if Task.isCancelled { break }
          continuation.yield(.speechStarted(at: segment.start))
          continuation.yield(.segment(segment))
          continuation.yield(.speechEnded(at: segment.end))
          clock = segment.end
        }
        continuation.yield(.ended)
        continuation.finish()
      }
      replay.set(task)
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func stop() async {
    await replay.end()
  }
}
