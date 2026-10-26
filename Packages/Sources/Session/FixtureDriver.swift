import Foundation
import Governor
import Transcription

/// Replays a fixture through a loop, inserting pause checks in every gap the
/// way the live client's timer would.
public enum FixtureDriver {
  public static func run(
    fixture: FixtureTranscriber.Fixture, config: GovernorConfig,
    policy: CompactionPolicy = .standard, dependencies: SessionLoop.Dependencies
  ) async -> SessionResult {
    let loop = SessionLoop(config: config, policy: policy, dependencies: dependencies)
    let finals = fixture.segments.filter(\.isFinal)
    for (index, segment) in finals.enumerated() {
      await loop.handle(.segment(segment))
      let next = index + 1 < finals.count ? finals[index + 1].start : TimeInterval.infinity
      while let tick = await loop.nextTick, tick < next {
        await loop.pause(until: tick)
      }
    }
    return await loop.finish()
  }
}

extension SessionLoop {
  func finish() async -> SessionResult {
    await end(at: lastSpeechEnd, byUser: true)
    return SessionResult(records: records, state: state, transcript: transcript)
  }
}
