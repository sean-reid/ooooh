import Foundation
import Transcription

/// Delivers another transcriber's events when the clock reaches their timestamps,
/// so a replay keeps the utterance durations it was recorded with.
public struct PacedTranscriber: Transcriber {
  let base: any Transcriber
  let speed: Double

  public init(_ base: any Transcriber, speed: Double = 1) {
    self.base = base
    self.speed = speed
  }

  public func events() -> AsyncStream<TranscriptEvent> {
    AsyncStream { continuation in
      let task = Task {
        let start = ContinuousClock.now
        for await event in base.events() {
          if let at = Self.time(of: event), speed.isFinite {
            let due = start + .seconds(at / speed)
            if due > .now {
              do {
                try await Task.sleep(until: due)
              } catch {
                break
              }
            }
          }
          continuation.yield(event)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func stop() async { await base.stop() }

  /// A final segment is known at its end; a volatile one at its start.
  static func time(of event: TranscriptEvent) -> TimeInterval? {
    switch event {
    case .speechStarted(let at), .speechEnded(let at): at
    case .segment(let segment): segment.isFinal ? segment.end : segment.start
    case .ended: nil
    }
  }
}
