import Foundation
import Governor
import State
import Testing
import Transcription

@testable import Session

/// A recording replays by the time of the check, not by its position in the run.
@Suite struct RecordedAnswersTests {
  func input(at now: TimeInterval, pause: TimeInterval, index: Int) -> CheckInput {
    CheckInput(
      state: .empty, recentTranscript: [],
      signals: Signals(now: now, pauseLength: pause, speechDensity: 1), checkIndex: index)
  }

  @Test func replaysTheAnswerGivenAtTheSameMoment() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("recorded-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    let live = ScriptedDecisionProvider { input in
      var answers = JevAnswers.quiet
      answers.cues["trailsOff"] = input.signals.pauseLength == 0 ? 0.9 : 0.1
      return answers
    }
    let recorder = try RecordingDecisionProvider(live, writingTo: url)
    _ = try await recorder.check(input(at: 10.5, pause: 0, index: 0))
    _ = try await recorder.check(input(at: 12.5, pause: 2, index: 1))
    try await recorder.close()

    let recorded = try RecordedDecisionProvider(contentsOf: url)
    let sameTimeNewIndex = try await recorded.check(input(at: 10.5, pause: 0, index: 7))
    let silence = try await recorded.check(input(at: 12.5, pause: 2, index: 0))
    let unseen = try await recorded.check(input(at: 15.5, pause: 5, index: 1))
    #expect(sameTimeNewIndex.cues["trailsOff"] == 0.9)
    #expect(silence.cues["trailsOff"] == 0.1)
    #expect(unseen == .quiet)
  }
}
