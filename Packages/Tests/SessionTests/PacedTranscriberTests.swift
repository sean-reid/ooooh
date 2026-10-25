import Foundation
import Testing
import Transcription

@testable import Session

@Suite struct PacedTranscriberTests {
  @Test func finalSegmentsArriveAtTheirEndTimes() async throws {
    let fixture = try SessionLoopTests().fixture()
    let clock = TestClock()
    let paced = PacedTranscriber(FixtureTranscriber(fixture: fixture), speed: 40, clock: clock)
    var iterator = paced.events().makeAsyncIterator()
    var arrivals = 0
    for segment in fixture.segments where segment.isFinal {
      for expected in [segment.start, segment.end] {
        let due = TestClock.Instant(offset: .seconds(expected / 40))
        while clock.sleeping == 0 { await Task.yield() }
        clock.advance(to: due)
        let event = await iterator.next()
        #expect(clock.now == due)
        switch event {
        case .speechStarted(let at): #expect(at == segment.start)
        case .segment(let got): #expect(got.end == segment.end)
        default: Issue.record("unexpected \(String(describing: event))")
        }
        arrivals += 1
      }
      let ended = await iterator.next()
      #expect(ended == .speechEnded(at: segment.end))
    }
    #expect(arrivals == 34)
    #expect(await iterator.next() == .ended)
  }

  @Test func infiniteSpeedNeverSleeps() async throws {
    let fixture = try SessionLoopTests().fixture()
    let clock = TestClock()
    let paced = PacedTranscriber(
      FixtureTranscriber(fixture: fixture), speed: .infinity, clock: clock)
    var count = 0
    for await _ in paced.events() { count += 1 }
    #expect(count == 52)
    #expect(clock.now.offset == .zero)
    #expect(clock.sleeping == 0)
  }
}
