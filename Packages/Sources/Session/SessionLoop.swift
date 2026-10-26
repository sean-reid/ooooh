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

  /// A decision waiting for the pause to hold. Phrasing runs while it waits.
  struct Arm {
    var kind: ArmedPrompt
    var due: TimeInterval
    var text: Task<String, Never>?
    /// The governor before the decision, restored when speech cuts the arm short.
    var governor: Governor
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
  var arm: Arm?
  var ending = false
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

  /// When the armed decision speaks, nil while nothing is armed.
  public var armDue: TimeInterval? { arm?.due }

  /// When the next silence check falls, nil while a decision is armed, once the schedule is
  /// spent, or after the session ended.
  public var nextCheckAt: TimeInterval? {
    guard !ended, arm == nil else { return nil }
    return governor.nextCheck(speechEnd: lastSpeechEnd)
  }

  /// The next time the clock has to call `pause(until:)`: the armed decision's due time or the
  /// next silence check.
  public var nextTick: TimeInterval? { [armDue, nextCheckAt].compactMap { $0 }.min() }

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
    case .speechStarted(let at):
      await resolveArm(speechAt: at)
    case .segment(let segment):
      await resolveArm(speechAt: segment.start)
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
    await speakArmed(by: now)
    guard !ended else { return }
    let pause = now - lastSpeechEnd
    await check(at: now, pause: pause, utteranceEnded: false)
  }

  /// Speaks the armed decision when `now` has reached its due time.
  public func speakArmed(by now: TimeInterval) async {
    guard let arm, now >= arm.due else { return }
    await speak(arm)
  }

  /// Speech at `at` either came after the due time, so the prompt spoke first, or cuts the arm short.
  func resolveArm(speechAt at: TimeInterval) async {
    guard let arm else { return }
    if at >= arm.due {
      await speak(arm)
    } else {
      cancel(arm, at: at)
    }
  }

  func check(at now: TimeInterval, pause: TimeInterval, utteranceEnded: Bool) async {
    guard arm == nil, !ending else { return }
    let signals = Signals(
      now: now, pauseLength: pause, speechDensity: density(at: now),
      awaitingFinishedReply: governor.finishedAskedAt != nil)
    guard governor.takeCheck(now: now, speechEnd: lastSpeechEnd, utteranceEnded: utteranceEnded)
    else { return }

    let input = CheckInput(
      state: state, recentTranscript: uncompacted, signals: signals, checkIndex: checkIndex)
    checkIndex += 1
    guard let answers = try? await deps.decisions.check(input) else { return }
    let before = governor
    let decision = governor.decide(answers, signals: signals)
    records.append(.check(at: now, index: input.checkIndex, answers: answers, decision: decision))

    switch decision {
    case .wait:
      break
    case .prompt(let kind):
      await arm(.intervention(kind), at: now, restoring: before)
    case .askIfFinished:
      await arm(.finishedQuestion, at: now, restoring: before)
    case .endSession:
      await end(at: now, byUser: false)
    case .command(let command):
      records.append(.command(at: now, command))
      if command == .wrapUp {
        await end(at: now, byUser: true)
      }
    }
  }

  /// Holds the decision until the pause since the last utterance end reaches the arming delay.
  func arm(_ kind: ArmedPrompt, at now: TimeInterval, restoring governor: Governor) async {
    var text: Task<String, Never>?
    if case .intervention(let kind) = kind {
      let (state, recent, phraser) = (state, uncompacted, deps.phraser)
      text = Task { (try? await phraser.phrase(kind, state: state, recent: recent)) ?? "" }
    }
    let due = max(lastSpeechEnd + config.armingDelay, now)
    arm = Arm(kind: kind, due: due, text: text, governor: governor)
    records.append(.promptArmed(at: now, kind: kind))
    await speakArmed(by: now)
  }

  func speak(_ arm: Arm) async {
    self.arm = nil
    switch arm.kind {
    case .intervention(let kind):
      let text = await arm.text?.value ?? ""
      state.lastIntervention = .init(kind: kind, text: text, at: arm.due)
      records.append(.prompt(at: arm.due, kind: kind, text: text))
    case .finishedQuestion:
      records.append(.askedIfFinished(at: arm.due))
    }
  }

  func cancel(_ arm: Arm, at now: TimeInterval) {
    self.arm = nil
    arm.text?.cancel()
    governor = arm.governor
    records.append(.promptCancelled(at: now))
  }

  /// The user has ended it. Segments still arriving are kept, but nothing is decided on them.
  func prepareToEnd() {
    ending = true
  }

  /// Folds whatever is still raw into the state, then closes the session.
  func end(at now: TimeInterval, byUser: Bool) async {
    guard !ended else { return }
    if let arm {
      cancel(arm, at: now)
    }
    if !uncompacted.isEmpty {
      await compactIfDue(at: now, force: true)
    }
    records.append(.ended(at: now, byUser: byUser))
    ended = true
  }

  func compactIfDue(at now: TimeInterval, force: Bool = false) async {
    let words = uncompacted.reduce(0) { $0 + $1.text.split(separator: " ").count }
    guard force || now - lastCompactionAt >= policy.everySeconds || words >= policy.everyWords
    else { return }
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
