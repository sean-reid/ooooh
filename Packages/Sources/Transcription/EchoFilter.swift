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
  /// A volatile inside a line's window that is not echo still waits for its final unless it has
  /// grown to this many words, which is a person talking over the line, not a misheard echo.
  static let interruptWords = 6

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
        switch state.judge(segment) {
        case .echo(let echo):
          state.heldStart = nil
          log(echo, segment, verdict: "dropped")
          return []
        case .held(let echo):
          log(echo, segment, verdict: "held")
          return []
        case .passed(let echo):
          log(echo, segment, verdict: "passed")
        case .outside:
          break
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

  private func log(_ echo: Echo, _ segment: Segment, verdict: String) {
    let engine = (base as? any LiveTranscriber)?.engine.rawValue ?? "unknown"
    transcriptionLog.info(
      """
      echo \(verdict, privacy: .public) \
      overlap=\(echo.overlap, format: .fixed(precision: 2), privacy: .public) \
      words=\(echo.words, privacy: .public) final=\(segment.isFinal, privacy: .public) \
      sinceLine=\(echo.sinceLine, format: .fixed(precision: 2), privacy: .public) \
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
    /// Seconds from the covering line's start to the segment's start.
    var sinceLine: TimeInterval
  }

  private enum Judgement {
    case outside
    case echo(Echo)
    case held(Echo)
    case passed(Echo)
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

    /// Echo when the best match among the lines whose window holds the segment's start clears the
    /// threshold or the segment is too short to judge. Otherwise a final passes, a volatile passes
    /// only at `interruptWords`, and a shorter volatile is held for its final.
    mutating func judge(_ segment: Segment) -> Judgement {
      lines.removeAll { $0.isPast(segment.start) }
      let words = EchoFilter.words(in: segment.text)
      guard !words.isEmpty else { return .outside }
      let covering = lines.filter { $0.covers(segment.start) }
      guard let best = covering.max(by: { score($0, words) < score($1, words) }) else {
        return .outside
      }
      let echo = Echo(
        overlap: score(best, words), words: words.count, sinceLine: segment.start - best.start)
      if echo.overlap >= threshold || words.count < minimumWords { return .echo(echo) }
      if segment.isFinal || words.count >= interruptWords { return .passed(echo) }
      return .held(echo)
    }

    private func score(_ line: Line, _ words: [String]) -> Double {
      Double(words.count { line.matches($0) }) / Double(words.count)
    }
  }
}
