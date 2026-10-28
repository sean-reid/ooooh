import Foundation
import Testing

@testable import Transcription

/// Every utterance here is what a recognizer emits: a start, growing volatile segments, the final one, an end.
@Suite struct EchoFilterTests {
  /// A microphone that yields its script in order and finishes; `stop()` is the `.ended` at the
  /// end of the script. Its audio clock reads `audioTime`.
  final class ScriptedTranscriber: LiveTranscriber, @unchecked Sendable {
    let engine = TranscriptionEngine.dictationTranscriber
    let audioTime: TimeInterval
    let script: [TranscriptEvent]
    private(set) var stops = 0

    init(_ script: [TranscriptEvent], audioTime: TimeInterval = 0) {
      self.script = script
      self.audioTime = audioTime
    }

    func downloadProgress() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func start() async throws {}

    func events() -> AsyncStream<TranscriptEvent> {
      AsyncStream { continuation in
        for event in script { continuation.yield(event) }
        continuation.finish()
      }
    }

    func stop() async { stops += 1 }
  }

  let line = "What sits underneath that?"

  func utterance(_ texts: [String], from start: TimeInterval, to end: TimeInterval)
    -> [TranscriptEvent]
  {
    var events: [TranscriptEvent] = [.speechStarted(at: start)]
    for text in texts.dropLast() {
      events.append(.segment(Segment(text: text, start: start, end: end - 0.2, isFinal: false)))
    }
    events.append(.segment(Segment(text: texts.last ?? "", start: start, end: end, isFinal: true)))
    events.append(.speechEnded(at: end))
    return events
  }

  func collect(_ filter: EchoFilter) async -> [TranscriptEvent] {
    var events: [TranscriptEvent] = []
    for await event in filter.events() { events.append(event) }
    return events
  }

  @Test func anEchoUtteranceDuringTheLineIsDroppedWhole() async {
    let echo = utterance(["What", "What sits under", line], from: 10.4, to: 11.9)
    let filter = EchoFilter(ScriptedTranscriber(echo + [.ended]))
    filter.spoke(line, from: 10.0)

    #expect(await collect(filter) == [.ended])
  }

  /// The echo of a line that began 1.5 s into the audio is timed on the microphone's clock,
  /// whatever the session clock says.
  @Test func aLineIsTimedOnTheMicrophonesClock() async {
    let echo = utterance(["What", "What sits under", line], from: 10.1, to: 11.6)
    let microphone = ScriptedTranscriber(echo + [.ended], audioTime: 10.0)
    let filter = EchoFilter(microphone)
    filter.spoke(line)
    #expect(filter.audioTime == 10.0)

    #expect(await collect(filter) == [.ended])
  }

  @Test func theSameWordsOutsideTheWindowPass() async {
    let later = utterance(["What", line], from: 13.1, to: 14.0)
    let filter = EchoFilter(ScriptedTranscriber(later + [.ended]))
    filter.spoke(line, from: 10.0)
    filter.finishedSpeaking(at: 12.0)

    #expect(await collect(filter) == later + [.ended])
  }

  /// A misheard echo can reach three words with little overlap, so a short volatile waits for
  /// its final; the final with the person's words passes with its start.
  @Test func aRealUtteranceDuringTheLinePassesAtItsFinal() async {
    let real = utterance(
      ["I think", "I think the price is wrong"], from: 10.5, to: 12.0)
    let filter = EchoFilter(ScriptedTranscriber(real + [.ended]))
    filter.spoke(line, from: 10.0)

    let passed = await collect(filter)
    #expect(passed.first == .speechStarted(at: 10.5))
    #expect(
      passed.contains(
        .segment(Segment(text: "I think the price is wrong", start: 10.5, end: 12.0, isFinal: true))
      ))
    #expect(
      !passed.contains(.segment(Segment(text: "I think", start: 10.5, end: 12.0, isFinal: false))))
    #expect(passed.last == .ended)
  }

  @Test func sixWordsOfRealSpeechDuringTheLinePassBeforeTheFinal() async {
    let interruption = Segment(
      text: "no wait I want to go back", start: 10.5, end: 11.4, isFinal: false)
    let script: [TranscriptEvent] = [.speechStarted(at: 10.5), .segment(interruption), .ended]
    let filter = EchoFilter(ScriptedTranscriber(script))
    filter.spoke(line, from: 10.0)

    #expect(await collect(filter) == [.speechStarted(at: 10.5), .segment(interruption), .ended])
  }

  @Test func aMisheardVolatileDuringTheLineIsHeldAndItsEchoFinalDropsIt() async {
    let misheard = Segment(text: "once it's under", start: 10.4, end: 11.0, isFinal: false)
    let script =
      [.speechStarted(at: 10.4), .segment(misheard)]
      + utterance([line], from: 10.4, to: 11.9).dropFirst() + [.ended]
    let filter = EchoFilter(ScriptedTranscriber(Array(script)))
    filter.spoke(line, from: 10.0)

    #expect(await collect(filter) == [.ended])
  }

  @Test func aShortFragmentDuringTheLineIsDroppedWhateverItSays() async {
    let filter = EchoFilter(ScriptedTranscriber([]))
    filter.spoke(line, from: 10.0)
    let fragment = Segment(text: "Whats", start: 10.5, end: 10.8, isFinal: false)
    let outside = Segment(text: "Whats", start: 20.0, end: 20.3, isFinal: false)

    #expect(filter.filter(.segment(fragment)).isEmpty)
    filter.finishedSpeaking(at: 12.0)
    #expect(filter.filter(.segment(outside)) == [.segment(outside)])
  }

  @Test func aPrefixCountsAsTheSameWord() async {
    let filter = EchoFilter(ScriptedTranscriber([]))
    filter.spoke(line, from: 10.0)
    let heard = Segment(text: "whats sits under the", start: 10.5, end: 11, isFinal: false)
    let other = Segment(text: "I think the price", start: 10.5, end: 11, isFinal: true)

    #expect(filter.filter(.segment(heard)).isEmpty)
    #expect(filter.filter(.segment(other)) == [.segment(other)])
  }

  @Test func anUtteranceThatStartsAsEchoKeepsTheUsersWordsFromTheFirstRealSegment() async {
    let mixed = "What sits underneath that yes but I want to go back to the price"
    let script = utterance(
      ["What sits", "What sits underneath that yes", mixed], from: 10.4, to: 14.0)
    let filter = EchoFilter(ScriptedTranscriber(script + [.ended]))
    filter.spoke(line, from: 10.0)

    let passed = await collect(filter)
    #expect(
      passed == [
        .speechStarted(at: 10.4),
        .segment(Segment(text: mixed, start: 10.4, end: 14.0, isFinal: true)),
        .speechEnded(at: 14.0),
        .ended,
      ])
  }

  @Test func endedPassesAfterAnUtteranceWasDropped() async {
    let script: [TranscriptEvent] = [
      .speechStarted(at: 10.4),
      .segment(Segment(text: "What sits", start: 10.4, end: 10.9, isFinal: false)),
      .speechEnded(at: 10.9),
      .ended,
    ]
    let filter = EchoFilter(ScriptedTranscriber(script))
    filter.spoke(line, from: 10.0)

    #expect(await collect(filter) == [.ended])
  }

  @Test func theWindowReachesThreeTenthsBeforeAndOneSecondAfterTheLine() async {
    let filter = EchoFilter(ScriptedTranscriber([]))
    filter.spoke(line, from: 10.0)
    filter.finishedSpeaking(at: 12.0)
    let inside = [9.7, 10.0, 12.0, 13.0].map {
      Segment(text: line, start: $0, end: $0, isFinal: false)
    }
    let outside = [9.69, 13.01].map { Segment(text: line, start: $0, end: $0, isFinal: false) }

    for segment in inside {
      #expect(filter.filter(.segment(segment)).isEmpty, "\(segment.start)")
    }
    for segment in outside {
      #expect(filter.filter(.segment(segment)) == [.segment(segment)], "\(segment.start)")
    }
  }

  @Test func sixtyPercentOfTheSegmentsWordsInTheLineIsEcho() async {
    let filter = EchoFilter(ScriptedTranscriber([]))
    filter.spoke(line, from: 10.0)
    let three = Segment(text: "what sits underneath my desk", start: 10.5, end: 11, isFinal: false)
    let two = Segment(text: "what sits on my desk", start: 10.5, end: 11, isFinal: true)

    #expect(filter.filter(.segment(three)).isEmpty)
    #expect(filter.filter(.segment(two)) == [.segment(two)])
  }

  @Test func wordsAreComparedWithoutCaseOrPunctuation() {
    #expect(
      EchoFilter.words(in: "Don't you think so? Yes, 2 of them.") == [
        "dont", "you", "think", "so", "yes", "2", "of", "them",
      ])
  }

  @Test func aLineStillPlayingHasNoEndAndStopReachesTheBase() async {
    let base = ScriptedTranscriber([])
    let filter = EchoFilter(base)
    filter.spoke(line, from: 10.0)
    let late = Segment(text: line, start: 40, end: 41, isFinal: false)

    #expect(filter.filter(.segment(late)).isEmpty)
    await filter.stop()
    #expect(base.stops == 1)
  }
}
