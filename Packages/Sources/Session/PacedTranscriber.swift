import Foundation
import Transcription

/// Delivers another transcriber's events when the clock reaches their timestamps,
/// so a replay keeps the utterance durations it was recorded with.
public struct PacedTranscriber<C: Clock>: Transcriber where C.Duration == Duration {
  let base: any Transcriber
  let speed: Double
  let clock: C
  let replay = ReplayTask()

  public init(_ base: any Transcriber, speed: Double = 1, clock: C) {
    self.base = base
    self.speed = speed
    self.clock = clock
  }

  public func events() -> AsyncStream<TranscriptEvent> {
    AsyncStream { continuation in
      let task = Task {
        let start = clock.now
        for await event in base.events() {
          if event == .ended { break }
          if let at = Self.time(of: event), speed.isFinite {
            let due = start.advanced(by: .seconds(at / speed))
            if due > clock.now {
              do {
                try await clock.sleep(until: due, tolerance: nil)
              } catch {
                break
              }
            }
          }
          if Task.isCancelled { break }
          continuation.yield(event)
        }
        continuation.yield(.ended)
        continuation.finish()
      }
      replay.set(task)
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Events the clock has not reached are dropped: the replay never said them.
  public func stop() async {
    await base.stop()
    await replay.end()
  }

  /// A final segment is known at its end; a volatile one at its start.
  static func time(of event: TranscriptEvent) -> TimeInterval? {
    switch event {
    case .speechStarted(let at), .speechEnded(let at): at
    case .segment(let segment): segment.isFinal ? segment.end : segment.start
    case .ended: nil
    }
  }
}

extension PacedTranscriber where C == ContinuousClock {
  public init(_ base: any Transcriber, speed: Double = 1) {
    self.init(base, speed: speed, clock: ContinuousClock())
  }
}
