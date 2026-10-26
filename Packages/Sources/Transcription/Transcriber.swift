import Foundation
import Synchronization

/// A piece of recognized speech. Partial results are replaced by the final one for the same range.
public struct Segment: Codable, Equatable, Sendable {
  public var text: String
  public var start: TimeInterval
  public var end: TimeInterval
  public var isFinal: Bool

  public init(text: String, start: TimeInterval, end: TimeInterval, isFinal: Bool) {
    self.text = text
    self.start = start
    self.end = end
    self.isFinal = isFinal
  }
}

public enum TranscriptEvent: Equatable, Sendable {
  case segment(Segment)
  case speechStarted(at: TimeInterval)
  case speechEnded(at: TimeInterval)
  case ended
}

/// Anything that turns audio into timed text. The live one wraps SpeechAnalyzer, the fixture one replays a file.
public protocol Transcriber: Sendable {
  func events() -> AsyncStream<TranscriptEvent>
  /// Finalises the open utterance into the stream, yields `.ended`, and returns once both are out. A second call is a no-op.
  func stop() async
}

/// The task feeding a replay stream, kept so `stop()` can end the stream before the replay runs out.
public final class ReplayTask: Sendable {
  private let task = Mutex<Task<Void, Never>?>(nil)

  public init() {}

  public func set(_ task: Task<Void, Never>) {
    self.task.withLock { $0 = task }
  }

  /// Cancels the replay and returns once its stream has finished.
  public func end() async {
    let task = self.task.withLock { $0 }
    task?.cancel()
    await task?.value
  }
}
