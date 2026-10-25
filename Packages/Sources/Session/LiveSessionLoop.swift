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
  let config: GovernorConfig
  let clock: LoopClock
  let levels: AsyncStream<Double>?
  let offline: AsyncStream<Bool>?
  let stream: AsyncStream<SessionEvent>
  let continuation: AsyncStream<SessionEvent>.Continuation

  private var consumer: Task<Void, Never>?
  private var forwarders: [Task<Void, Never>] = []
  private var timer: Task<Void, Never>?
  private var nextTick: TimeInterval?
  private var armDue: TimeInterval?
  private var emitted = 0
  private var loopEnded = false
  private var completed = false
  private var startedAt: Duration?

  public init<C: Clock>(
    config: GovernorConfig, policy: CompactionPolicy = .standard,
    dependencies: SessionLoop.Dependencies, transcriber: any Transcriber,
    levels: AsyncStream<Double>? = nil, offline: AsyncStream<Bool>? = nil, clock: C
  ) where C.Duration == Duration {
    let (stream, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
    var dependencies = dependencies
    dependencies.phraser = AnnouncingPhraser(base: dependencies.phraser) { kind in
      continuation.yield(.promptPending(kind))
    }
    self.loop = SessionLoop(config: config, policy: policy, dependencies: dependencies)
    self.transcriber = transcriber
    self.config = config
    self.clock = LoopClock(clock)
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

  /// The user ended it. Stops the transcriber, folds what is left, and emits `.ended`.
  public func end() async {
    consumer?.cancel()
    await complete()
  }

  private func consume() async {
    events: for await event in transcriber.events() {
      if Task.isCancelled || completed { break }
      switch event {
      case .speechStarted(let at):
        await catchUp(before: at)
        cancelTimer()
        continuation.yield(.speechStarted(at: at))
        await loop.handle(event)
        await drain()
      case .segment(let segment):
        if segment.isFinal {
          await catchUp(before: segment.start)
          cancelTimer()
        }
        await loop.handle(event)
        await drain()
        if segment.isFinal, !loopEnded {
          continuation.yield(.utterance(segment))
          nextTick = segment.end + config.checkPause
          scheduleTimer()
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

  /// Sleeps until the earlier of the next pause check and the armed decision's due time.
  private func scheduleTimer() {
    timer?.cancel()
    guard let due = [nextTick, armDue].compactMap({ $0 }).min(), let startedAt else { return }
    timer = Task {
      let deadline = startedAt + .seconds(due)
      if deadline > clock.now() { try? await clock.sleep(deadline) }
      guard !Task.isCancelled else { return }
      await fire(due)
    }
  }

  private func fire(_ due: TimeInterval) async {
    guard !completed else { return }
    if armDue == due {
      await loop.speakArmed(by: due)
      await drain()
    }
    if nextTick == due {
      nextTick = due + config.minCheckInterval
      await loop.pause(until: due)
      await drain()
    }
    if loopEnded {
      await complete()
    } else {
      scheduleTimer()
    }
  }

  /// Runs the ticks the clock has not reached that fall before `start`, in order.
  private func catchUp(before start: TimeInterval) async {
    while let tick = nextTick, tick < start, !completed, !loopEnded {
      nextTick = tick + config.minCheckInterval
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

  private func complete() async {
    guard !completed else { return }
    completed = true
    cancelTimer()
    for task in forwarders { task.cancel() }
    await transcriber.stop()
    let result = await loop.finish()
    continuation.yield(.ended(result))
    continuation.finish()
  }
}

extension SessionLoop {
  func snapshot() -> (records: [SessionRecord], state: CompactState, armDue: TimeInterval?) {
    (records, state, armDue)
  }
}

/// Any clock, read as the offset since it was wrapped, so tests drive the loop with a clock they advance by hand.
struct LoopClock: Sendable {
  let now: @Sendable () -> Duration
  let sleep: @Sendable (Duration) async throws -> Void

  init<C: Clock>(_ clock: C) where C.Duration == Duration {
    let origin = clock.now
    now = { origin.duration(to: clock.now) }
    sleep = { try await clock.sleep(until: origin.advanced(by: $0), tolerance: nil) }
  }
}

/// Tells the screen a prompt is coming before the phraser has the words.
struct AnnouncingPhraser: Phraser {
  let base: any Phraser
  let announce: @Sendable (InterventionKind) -> Void

  func phrase(_ kind: InterventionKind, state: CompactState, recent: [Segment]) async throws
    -> String
  {
    try Task.checkCancellation()
    announce(kind)
    return try await base.phrase(kind, state: state, recent: recent)
  }
}
