import Foundation
import Governor
import State
import Transcription

/// When the raw transcript gets folded into the compact state.
public struct CompactionPolicy: Equatable, Sendable {
  public var everySeconds: TimeInterval
  public var everyWords: Int

  public init(everySeconds: TimeInterval = 300, everyWords: Int = 600) {
    self.everySeconds = everySeconds
    self.everyWords = everyWords
  }

  public static let standard = CompactionPolicy()
}

/// Drives one session from transcript events to records. Time comes from the
/// segments, so a fixture replays identically every run.
public actor SessionLoop {
  public struct Dependencies: Sendable {
    public var decisions: any DecisionProvider
    public var compactor: any Compactor
    public var phraser: any Phraser

    public init(decisions: any DecisionProvider, compactor: any Compactor, phraser: any Phraser) {
      self.decisions = decisions
      self.compactor = compactor
      self.phraser = phraser
    }
  }

  let config: GovernorConfig
  let policy: CompactionPolicy
  let deps: Dependencies

  var governor: Governor
  var state: CompactState
  var transcript: [Segment] = []
  var uncompacted: [Segment] = []
  var records: [SessionRecord] = []
  var checkIndex = 0
  var lastCompactionAt: TimeInterval = 0
  var lastSpeechEnd: TimeInterval = 0
  var ended = false

  public init(
    config: GovernorConfig, policy: CompactionPolicy = .standard, state: CompactState = .empty,
    dependencies: Dependencies
  ) {
    self.config = config
    self.policy = policy
    self.deps = dependencies
    self.governor = Governor(config: config)
    self.state = state
  }

  /// Consumes the whole stream and returns what happened.
  public func run(_ transcriber: any Transcriber) async -> SessionResult {
    for await event in transcriber.events() {
      if ended { break }
      await handle(event)
    }
    if !ended {
      records.append(.ended(at: lastSpeechEnd, byUser: true))
    }
    return SessionResult(records: records, state: state, transcript: transcript)
  }

  func handle(_ event: TranscriptEvent) async {
    switch event {
    case .speechStarted:
      break
    case .segment(let segment):
      guard segment.isFinal else { return }
      transcript.append(segment)
      uncompacted.append(segment)
      lastSpeechEnd = segment.end
      await compactIfDue(at: segment.end)
      await check(at: segment.end, pause: 0, utteranceEnded: true)
    case .speechEnded(let at):
      lastSpeechEnd = max(lastSpeechEnd, at)
    case .ended:
      break
    }
  }

  /// A pause the client measured with no new speech. The fixture driver calls this
  /// for the gap after each segment; the live client calls it on a timer.
  public func pause(until now: TimeInterval) async {
    guard !ended else { return }
    let pause = now - lastSpeechEnd
    await check(at: now, pause: pause, utteranceEnded: false)
  }

  func check(at now: TimeInterval, pause: TimeInterval, utteranceEnded: Bool) async {
    let signals = Signals(
      now: now, pauseLength: pause, speechDensity: density(at: now),
      awaitingFinishedReply: governor.finishedAskedAt != nil)
    guard governor.shouldCheck(signals: signals, utteranceEnded: utteranceEnded) else { return }

    let input = CheckInput(
      state: state, recentTranscript: uncompacted, signals: signals, checkIndex: checkIndex)
    checkIndex += 1
    guard let answers = try? await deps.decisions.check(input) else { return }
    let decision = governor.decide(answers, signals: signals)
    records.append(.check(at: now, index: input.checkIndex, answers: answers, decision: decision))

    switch decision {
    case .wait:
      break
    case .prompt(let kind):
      let text = (try? await deps.phraser.phrase(kind, state: state, recent: uncompacted)) ?? ""
      state.lastIntervention = .init(kind: kind, text: text, at: now)
      records.append(.prompt(at: now, kind: kind, text: text))
    case .askIfFinished:
      records.append(.askedIfFinished(at: now))
    case .endSession:
      records.append(.ended(at: now, byUser: false))
      ended = true
    case .command(let command):
      records.append(.command(at: now, command))
      if command == .wrapUp {
        records.append(.ended(at: now, byUser: true))
        ended = true
      }
    }
  }

  func compactIfDue(at now: TimeInterval) async {
    let words = uncompacted.reduce(0) { $0 + $1.text.split(separator: " ").count }
    guard now - lastCompactionAt >= policy.everySeconds || words >= policy.everyWords else {
      return
    }
    guard let patch = try? await deps.compactor.compact(state: state, transcript: uncompacted)
    else { return }
    do {
      state = try state.applying(patch)
      records.append(.compaction(at: now, patch: patch))
      uncompacted.removeAll()
      lastCompactionAt = now
    } catch {
      records.append(.compactionRejected(at: now, reason: "\(error)"))
    }
  }

  /// Fraction of the trailing window covered by speech.
  func density(at now: TimeInterval) -> Double {
    let window = config.densityWindow
    let start = max(0, now - window)
    guard now > start else { return 1 }
    let spoken = transcript.reduce(0.0) { total, segment in
      total + max(0, min(segment.end, now) - max(segment.start, start))
    }
    return min(1, spoken / (now - start))
  }
}
