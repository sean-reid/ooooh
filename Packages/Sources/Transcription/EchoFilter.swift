import Foundation
import Synchronization

/// Drops what the microphone hears of the app's own lines: a segment inside a spoken line's window that shares most of its words.
public final class EchoFilter: Transcriber, Sendable {
  /// How far a line's window reaches before it starts and after it ends, for the recognizer's lag.
  static let leadIn: TimeInterval = 0.3
  static let tail: TimeInterval = 1.0
  /// The fraction of a segment's words that must be in the line for the segment to be echo.
  static let threshold = 0.6
  /// A fragment shorter than this inside a line's window is too little to judge and is dropped;
  /// the recognizer's next, longer result carries the same words again.
  static let minimumWords = 3

  private let base: any Transcriber
  private let clock: @Sendable () -> TimeInterval
  private let state = Mutex(State())

  /// `clock` reads the microphone's audio time, the clock the base's segment times are on.
  public init(_ base: any Transcriber, clock: @escaping @Sendable () -> TimeInterval) {
    self.base = base
    self.clock = clock
  }

  public convenience init(_ live: any LiveTranscriber) {
    self.init(live, clock: { live.audioTime })
  }

  /// The microphone's audio time now.
  public var audioTime: TimeInterval { clock() }

  /// A line began playing now.
  public func spoke(_ text: String) { spoke(text, from: clock()) }

  /// A line began playing at `start` on the microphone's clock.
  public func spoke(_ text: String, from start: TimeInterval) {
    state.withLock { $0.lines.append(Line(words: Set(Self.words(in: text)), start: start)) }
  }

  /// The line playing stopped now, finished or cut.
  public func finishedSpeaking() { finishedSpeaking(at: clock()) }

  /// The line playing stopped at `end`, finished or cut. Nothing playing, nothing changes.
  public func finishedSpeaking(at end: TimeInterval) {
    state.withLock { state in
      guard let index = state.lines.lastIndex(where: { $0.end == nil }) else { return }
      state.lines[index].end = end
    }
  }

  public func events() -> AsyncStream<TranscriptEvent> {
    AsyncStream { continuation in
      let task = Task {
        for await event in base.events() {
          for passed in filter(event) {
            continuation.yield(passed)
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func stop() async {
    await base.stop()
  }

  /// A speech start is held until the next event decides it: an echo segment takes the start
  /// down with it, anything else lets both through in order. An utterance whose start was
  /// dropped gets a new one at its first real segment, and its end passes only after a start did.
  func filter(_ event: TranscriptEvent) -> [TranscriptEvent] {
    state.withLock { state in
      switch event {
      case .speechStarted(let at):
        let passed = state.flushHeld()
        state.heldStart = at
        state.inUtterance = true
        state.passedStart = false
        return passed
      case .segment(let segment):
        if let echo = state.echo(segment) {
          state.heldStart = nil
          log(echo, segment)
          return []
        }
        var passed = state.flushHeld()
        if state.inUtterance, !state.passedStart {
          passed.append(.speechStarted(at: segment.start))
          state.passedStart = true
        }
        passed.append(event)
        return passed
      case .speechEnded:
        var passed = state.flushHeld()
        if state.passedStart { passed.append(event) }
        state.inUtterance = false
        state.passedStart = false
        return passed
      case .ended:
        return state.flushHeld() + [event]
      }
    }
  }

  /// Lowercased with punctuation stripped, so a word matches however the recognizer spells it.
  static func words(in text: String) -> [String] {
    text.lowercased().split(whereSeparator: \.isWhitespace)
      .map { String($0.filter { $0.isLetter || $0.isNumber }) }
      .filter { !$0.isEmpty }
  }

  private func log(_ echo: Echo, _ segment: Segment) {
    let engine = (base as? any LiveTranscriber)?.engine.rawValue ?? "unknown"
    transcriptionLog.info(
      """
      echo dropped overlap=\(echo.overlap, format: .fixed(precision: 2), privacy: .public) \
      words=\(echo.words, privacy: .public) final=\(segment.isFinal, privacy: .public) \
      engine=\(engine, privacy: .public)
      """)
  }

  private struct Line {
    var words: Set<String>
    var start: TimeInterval
    var end: TimeInterval?

    /// Equal, or one word a prefix of the other from three letters on, so "whats" meets "what".
    func matches(_ word: String) -> Bool {
      if words.contains(word) { return true }
      guard word.count >= 3 else { return false }
      return words.contains { $0.count >= 3 && ($0.hasPrefix(word) || word.hasPrefix($0)) }
    }

    func covers(_ time: TimeInterval) -> Bool {
      guard time >= start - leadIn else { return false }
      guard let end else { return true }
      return time <= end + tail
    }

    /// True once the window has closed before `time`, so no later segment can fall in it.
    func isPast(_ time: TimeInterval) -> Bool {
      guard let end else { return false }
      return end + tail < time
    }
  }

  private struct Echo {
    var overlap: Double
    var words: Int
  }

  private struct State {
    var lines: [Line] = []
    var heldStart: TimeInterval?
    var inUtterance = false
    var passedStart = false

    mutating func flushHeld() -> [TranscriptEvent] {
      guard let held = heldStart else { return [] }
      heldStart = nil
      passedStart = true
      return [.speechStarted(at: held)]
    }

    /// The best match among the lines whose window holds the segment's start, when it clears the
    /// threshold or the segment is too short to judge.
    mutating func echo(_ segment: Segment) -> Echo? {
      lines.removeAll { $0.isPast(segment.start) }
      let words = EchoFilter.words(in: segment.text)
      guard !words.isEmpty else { return nil }
      let covering = lines.filter { $0.covers(segment.start) }
      guard !covering.isEmpty else { return nil }
      let overlap =
        covering.map { line in
          Double(words.count { line.matches($0) }) / Double(words.count)
        }.max() ?? 0
      guard overlap >= threshold || words.count < minimumWords else { return nil }
      return Echo(overlap: overlap, words: words.count)
    }
  }
}
