import Foundation
import Governor
import State
import Testing

@testable import Session

@Suite struct RecordingTests {
  @Test func recordedAnswersReadBackByCheckIndex() async throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "recording-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }

    let stub = ScriptedDecisionProvider { input in
      var answers = JevAnswers.quiet
      answers.goodMoment = .init(0.1 * Double(input.checkIndex + 1))
      answers.intervention = .init(.deepen, confidence: 0.4)
      answers.cues = ["trailsOff": 0.7]
      return answers
    }
    let recorder = try RecordingDecisionProvider(stub, writingTo: url)
    let inputs = (0..<3).map {
      CheckInput(
        state: .empty, recentTranscript: [],
        signals: Signals(now: Double($0), pauseLength: 0, speechDensity: 1), checkIndex: $0)
    }
    var written: [JevAnswers] = []
    for input in inputs {
      written.append(try await recorder.check(input))
    }
    try await recorder.close()
    #expect(await recorder.count == 3)

    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 3)
    let entry = try JSONDecoder().decode(
      RecordedDecisionProvider.Entry.self, from: Data(lines[1].utf8))
    #expect(entry.checkIndex == 1)
    #expect(entry.answers == written[1])

    let replay = try RecordedDecisionProvider(contentsOf: url)
    for (input, answers) in zip(inputs, written) {
      #expect(try await replay.check(input) == answers)
    }
    let missing = CheckInput(
      state: .empty, recentTranscript: [],
      signals: Signals(now: 9, pauseLength: 0, speechDensity: 1), checkIndex: 9)
    #expect(try await replay.check(missing) == .quiet)
  }
}
