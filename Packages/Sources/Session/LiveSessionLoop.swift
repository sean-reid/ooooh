import Foundation
import Governor
import State
import Transcription

/// Runs a loop against a transcriber on the wall clock. The gaps between
/// utterances get the pause checks `FixtureDriver` inserts: a timer fires them
/// when the clock is ahead of the transcriber, and the next utterance catches
/// up any that the clock did not reach, so a fixture at any speed yields the
/// records the driver would.
public actor LiveSessionLoop {
  let loop: SessionLoop
  let transcriber: any Transcriber
  let config: GovernorConfig
  let levels: AsyncStream<Double>?
  let offline: AsyncStream<Bool>?
  let stream: AsyncStream<SessionEvent>
  let continuation: AsyncStream<SessionEvent>.Continuation

  private var consumer: Task<Void, Never>?
  private var forwarders: [Task<Void, Never>] = []
  private var timer: Task<Void, Never>?
  private var nextTick: TimeInterval?
  private var emitted = 0
  private var loopEnded = false
  private var completed = false
  private var startedAt: ContinuousClock.Instant?

  public init(
    config: GovernorConfig, policy: CompactionPolicy = .standard,
    dependencies: SessionLoop.Dependencies, transcriber: any Transcriber,
    levels: AsyncStream<Double>? = nil, offline: AsyncStream<Bool>? = nil
  ) {
    let (stream, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
    var dependencies = dependencies
    dependencies.phraser = AnnouncingPhraser(base: dependencies.phraser) { kind in
      continuation.yield(.promptPending(kind))
    }
    self.loop = SessionLoop(config: config, policy: policy, dependencies: dependencies)
    self.transcriber = transcriber
    self.config = config
    self.levels = levels
    self.offline = offline
    self.stream = stream
    self.continuation = continuation
  }

  public nonisolated func events() -> AsyncStream<SessionEvent> { stream }

  public func start() {
    guard consumer == nil, !completed else { return }
    startedAt = .now
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
      case .segment(let segment):
        if segment.isFinal {
          await catchUp(before: segment.start)
          cancelTimer()
        }
        await loop.handle(event)
        await drain()
        if segment.isFinal, !loopEnded {
          continuation.yield(.utterance(segment))
          schedule(from: segment.end)
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

  private func schedule(from end: TimeInterval) {
    nextTick = end + config.checkPause
    arm()
  }

  private func arm() {
    timer?.cancel()
    guard let tick = nextTick, let startedAt else { return }
    timer = Task {
      let elapsed = startedAt.duration(to: .now)
      let wait = tick - elapsed.seconds
      if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
      guard !Task.isCancelled else { return }
      await fire(tick)
    }
  }

  private func fire(_ tick: TimeInterval) async {
    guard !completed, nextTick == tick else { return }
    nextTick = tick + config.minCheckInterval
    await loop.pause(until: tick)
    await drain()
    if loopEnded {
      await complete()
    } else {
      arm()
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
    let (records, state) = await loop.snapshot()
    guard !completed, records.count > emitted else { return }
    let fresh = records[emitted...]
    emitted = records.count
    for record in fresh {
      switch record {
      case .prompt(let at, let kind, let text):
        continuation.yield(.promptRequested(kind: kind, text: text, at: at))
      case .askedIfFinished(let at):
        continuation.yield(.askedIfFinished(at: at))
      case .compaction(let at, _):
        continuation.yield(.compactionApplied(state, at: at))
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
  func snapshot() -> (records: [SessionRecord], state: CompactState) {
    (records, state)
  }
}

extension Duration {
  var seconds: TimeInterval {
    let parts = components
    return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
  }
}

/// Tells the screen a prompt is coming before the phraser has the words.
struct AnnouncingPhraser: Phraser {
  let base: any Phraser
  let announce: @Sendable (InterventionKind) -> Void

  func phrase(_ kind: InterventionKind, state: CompactState, recent: [Segment]) async throws
    -> String
  {
    announce(kind)
    return try await base.phrase(kind, state: state, recent: recent)
  }
}
