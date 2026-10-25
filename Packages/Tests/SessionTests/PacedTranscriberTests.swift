import Foundation
import Testing
import Transcription

@testable import Session

@Suite struct PacedTranscriberTests {
  @Test func finalSegmentsArriveAtTheirEndTimes() async throws {
    let fixture = try SessionLoopTests().fixture()
    let paced = PacedTranscriber(FixtureTranscriber(fixture: fixture), speed: 40)
    let clock = ContinuousClock()
    let start = clock.now
    var arrivals: [(expected: TimeInterval, actual: TimeInterval)] = []
    for await event in paced.events() {
      switch event {
      case .speechStarted(let at):
        arrivals.append((at / 40, start.duration(to: clock.now).seconds))
      case .segment(let segment):
        arrivals.append((segment.end / 40, start.duration(to: clock.now).seconds))
      default:
        break
      }
    }
    #expect(arrivals.count == 34)
    for (expected, actual) in arrivals {
      #expect(actual >= expected - 0.001)
      #expect(actual - expected < 0.15)
    }
    let total = start.duration(to: clock.now).seconds
    #expect(total >= 87.8 / 40)
  }

  @Test func infiniteSpeedNeverWaits() async throws {
    let fixture = try SessionLoopTests().fixture()
    let paced = PacedTranscriber(FixtureTranscriber(fixture: fixture), speed: .infinity)
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
      var count = 0
      for await _ in paced.events() { count += 1 }
      #expect(count == 52)
    }
    #expect(elapsed < .milliseconds(100))
  }
}
