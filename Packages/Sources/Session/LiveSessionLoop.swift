import Foundation
import Governor
import State
import Transcription

/// Runs a loop against a transcriber on a clock. The gaps between utterances
/// get the pause checks `FixtureDriver` inserts: a timer fires them when the
/// clock is ahead of the transcriber, and the next utterance catches up any
/// that the clock did not reach, so a fixture at any speed yields the records
/// the driver would. The same timer speaks an armed decision when its pause
/// has held.
public actor LiveSessionLoop {
  let loop: SessionLoop
  let transcriber: any Transcriber
  let clock: OffsetClock
  let levels: AsyncStream<Double>?
  let offline: AsyncStream<Bool>?
  let stream: AsyncStream<SessionEvent>
  let continuation: AsyncStream<SessionEvent>.Continuation

  private var consumer: Task<Void, Never>?
  private var forwarders: [Task<Void, Never>] = []
  private var timer: Task<Void, Never>?
  private var nextTick: TimeInterval?
  private var armDue: TimeInterval?
  /// Set from a final segment to the next speech start; only then do silence checks run.
  private var inPause = false
  private var emitted = 0
  private var loopEnded = false
  private var ending = false
  private var stopped = false
  private var completed = false
  private var startedAt: Duration?
  private var pausedAt: Duration?
  /// The transcriber's clock at the pause while one holds; speech timed after it was heard paused.
  private var pauseCutoff: TimeInterval?
  private var paused = false

  /// How long End waits for the transcriber to finalise and end its stream before the loop stops reading.
  static let stopGrace: Duration = .seconds(5)

  public init<C: Clock>(
    config: GovernorConfig, policy: CompactionPolicy = .standard,
    dependencies: SessionLoop.Dependencies, transcriber: any Transcriber,
    levels: AsyncStream<Double>? = nil, offline: AsyncStream<Bool>? = nil, clock: C
  ) where C.Duration == Duration {
    let (stream, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
    self.loop = SessionLoop(config: config, policy: policy, dependencies: dependencies)
    self.transcriber = transcriber
    self.clock = OffsetClock(clock)
    self.levels = levels
    self.offline = offline
    self.stream = stream
    self.continuation = continuation
  }

  public init(
    config: GovernorConfig, policy: CompactionPolicy = .standard,
    dependencies: SessionLoop.Dependencies, transcriber: any Transcriber,
    levels: AsyncStream<Double>? = nil, offline: AsyncStream<Bool>? = nil
  ) {
    self.init(
      config: config, policy: policy, dependencies: dependencies, transcriber: transcriber,
      levels: levels, offline: offline, clock: ContinuousClock())
  }

  public nonisolated func events() -> AsyncStream<SessionEvent> { stream }

  public func start() {
    guard consumer == nil, !completed else { return }
    startedAt = clock.now()
    consumer = Task { await consume() }
    if let levels {
      forwarders.append(
        Task {
          for await level in levels { continuation.yield(.speechLevel(level)) }
        })
    }
    if let offline {
      forwarders.append(
        Task {
          for await state in offline { continuation.yield(.offline(state)) }
        })
    }
  }

  /// The user ended it. Stops the transcriber, reads what it finalises up to `.ended`, folds what is
  /// left, and emits `.ended`. A stream still open after `stopGrace` is abandoned.
  public func end() async {
    guard !completed, !ending else { return }
    ending = true
    cancelTimer()
    await loop.prepareToEnd()
    await stopTranscriber()
    if let consumer {
      let watchdog = Task { [clock] in
        try? await clock.sleep(clock.now() + Self.stopGrace)
        guard !Task.isCancelled else { return }
        consumer.cancel()
      }
      await consumer.value
      watchdog.cancel()
    }
    await complete()
  }

  /// Holds the timer, cancels the armed decision, and drops speech until `resume()`. `audioTime`
  /// is the transcriber's clock now; what it finalises from before the pause still lands, and
  /// without one everything heard while paused is dropped.
  public func pause(audioTime: TimeInterval? = nil) async {
    guard !completed, !ending, !paused, let startedAt else { return }
    paused = true
    let now = clock.now()
    pausedAt = now
    pauseCutoff = audioTime
    cancelTimer()
    await loop.cancelArm(at: audioTime ?? Self.seconds(now - startedAt))
    await drain()
  }

  /// Moves the session's start forward by the pause, so the timer picks the schedule up where
  /// it stopped.
  public func resume() async {
    guard paused, let pausedAt, let startedAt else { return }
    paused = false
    self.startedAt = startedAt + (clock.now() - pausedAt)
    self.pausedAt = nil
    pauseCutoff = nil
    guard !completed, !ending else { return }
    await drain()
    if inPause { scheduleTimer() }
  }

  /// True for speech the paused transcriber reports past the cutoff, or any speech without one.
  static func heardWhilePaused(_ event: TranscriptEvent, after cutoff: TimeInterval?) -> Bool {
    let at: TimeInterval
    switch event {
    case .speechStarted(let time), .speechEnded(let time): at = time
    case .segment(let segment): at = segment.start
    case .ended: return false
    }
    guard let cutoff else { return true }
    return at > cutoff
  }

  static func seconds(_ duration: Duration) -> TimeInterval {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) + Double(attoseconds) / 1e18
  }

  private func consume() async {
    events: for await event in transcriber.events() {
      if Task.isCancelled || completed { break }
      if paused, Self.heardWhilePaused(event, after: pauseCutoff) { continue }
      switch event {
      case .speechStarted(let at):
        await catchUp(before: at)
        cancelTimer()
        inPause = false
        continuation.yield(.speechStarted(at: at))
        await loop.handle(event)
        await drain()
      case .segment(let segment):
        if segment.isFinal {
          await catchUp(before: segment.start)
          cancelTimer()
        }
        await loop.handle(event)
        if segment.isFinal { inPause = true }
        await drain()
        if segment.isFinal, !loopEnded {
          continuation.yield(.utterance(segment))
          if !ending, !paused { scheduleTimer() }
        }
      case .speechEnded(let at):
        await loop.handle(event)
        continuation.yield(.speechEnded(at: at))
      case .ended:
        break events
      }
      if loopEnded { break }
    }
    await complete()
  }

  /// Sleeps until the earlier of the next silence check and the armed decision's due time.
  private func scheduleTimer() {
    timer?.cancel()
    guard let due = nextDue, let startedAt else { return }
    timer = Task {
      let deadline = startedAt + .seconds(due)
      if deadline > clock.now() { try? await clock.sleep(deadline) }
      guard !Task.isCancelled else { return }
      await fire(due)
    }
  }

  private var nextDue: TimeInterval? { [nextTick, armDue].compactMap { $0 }.min() }

  /// One tick: speaks the armed decision when it is due and runs the silence check when one is.
  private func fire(_ due: TimeInterval) async {
    guard !completed, !ending else { return }
    await loop.pause(until: due)
    await drain()
    if loopEnded {
      await complete()
    } else {
      scheduleTimer()
    }
  }

  /// Runs the ticks the clock has not reached that fall before `start`, in order.
  private func catchUp(before start: TimeInterval) async {
    while let tick = nextDue, tick < start, !completed, !loopEnded {
      await loop.pause(until: tick)
      await drain()
    }
  }

  private func cancelTimer() {
    timer?.cancel()
    timer = nil
    nextTick = nil
  }

  private func drain() async {
    let snapshot = await loop.snapshot()
    armDue = snapshot.armDue
    nextTick = inPause ? snapshot.nextCheckAt : nil
    guard !completed, snapshot.records.count > emitted else { return }
    let fresh = snapshot.records[emitted...]
    emitted = snapshot.records.count
    for record in fresh {
      switch record {
      case .promptArmed(let at, let kind):
        continuation.yield(.promptArmed(at: at, kind: kind))
      case .promptCancelled(let at):
        continuation.yield(.promptCancelled(at: at))
      case .prompt(let at, let kind, let text):
        continuation.yield(.promptRequested(kind: kind, text: text, at: at))
      case .askedIfFinished(let at):
        continuation.yield(.askedIfFinished(at: at))
      case .compaction(let at, _):
        continuation.yield(.compactionApplied(snapshot.state, at: at))
      case .ended:
        loopEnded = true
      case .check, .command, .compactionRejected:
        break
      }
    }
  }

  private func stopTranscriber() async {
    guard !stopped else { return }
    stopped = true
    await transcriber.stop()
  }

  private func complete() async {
    guard !completed else { return }
    completed = true
    cancelTimer()
    for task in forwarders { task.cancel() }
    await stopTranscriber()
    let result = await loop.finish()
    continuation.yield(.ended(result))
    continuation.finish()
  }
}

extension SessionLoop {
  func snapshot() -> (
    records: [SessionRecord], state: CompactState, armDue: TimeInterval?,
    nextCheckAt: TimeInterval?
  ) {
    (records, state, armDue, nextCheckAt)
  }
}
