import Foundation
import Governor
import Transcription

/// Replays a fixture through a loop, inserting pause checks in every gap the
/// way the live client's timer would. After the last utterance the user ends the session
/// before the long-silence check, unless the finished question is already out and the end
/// check decides.
public enum FixtureDriver {
  public static func run(
    fixture: FixtureTranscriber.Fixture, config: GovernorConfig,
    policy: CompactionPolicy = .standard, dependencies: SessionLoop.Dependencies
  ) async -> SessionResult {
    let loop = SessionLoop(config: config, policy: policy, dependencies: dependencies)
    let finals = fixture.segments.filter(\.isFinal)
    for (index, segment) in finals.enumerated() {
      await loop.handle(.segment(segment))
      let last = index + 1 == finals.count
      let next = last ? TimeInterval.infinity : finals[index + 1].start
      while let tick = await loop.nextTick, tick < next {
        if last, tick >= segment.end + config.longSilence,
          await loop.governor.finishedAskedAt == nil
        {
          break
        }
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
