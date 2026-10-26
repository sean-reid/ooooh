import Audio
import Foundation

enum SpeechEvent: Equatable, Sendable {
  case started
  case finished
}

/// Says one prompt aloud. The stream reports when sound starts and when it ends or is cut off, then finishes.
protocol PromptSpeaking: Sendable {
  func speak(text: String) -> AsyncStream<SpeechEvent>
  func stop() async
}

/// Says nothing, and takes about as long as reading the line would.
struct SilentSpeaker: PromptSpeaking {
  func speak(text: String) -> AsyncStream<SpeechEvent> {
    AsyncStream { continuation in
      let words = text.split(separator: " ").count
      let task = Task {
        continuation.yield(.started)
        try? await Task.sleep(for: .seconds(max(1.5, Double(words) * 0.35)))
        continuation.yield(.finished)
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func stop() async {}
}

/// Voice mode: the Worker's MP3 stream through the barge-in player. One line at a time; a new line cuts the old one off, and so does dropping a line's stream.
actor VoiceSpeaker: PromptSpeaking {
  private typealias Continuation = AsyncStream<SpeechEvent>.Continuation

  private struct Line {
    let events: Continuation
    let done: CheckedContinuation<Void, Never>
  }

  private let player = PromptSpeaker()
  private let audio: @Sendable (String) -> AsyncThrowingStream<Data, Error>
  private var line: Line?
  private var generation = 0
  private var playing: Task<Void, Never>?
  private var forwarder: Task<Void, Never>?

  init(audio: @escaping @Sendable (String) -> AsyncThrowingStream<Data, Error>) {
    self.audio = audio
  }

  var hasEngine: Bool {
    get async { await player.hasEngine }
  }

  nonisolated func speak(text: String) -> AsyncStream<SpeechEvent> {
    AsyncStream { continuation in
      let request = Task { await self.play(text, into: continuation) }
      continuation.onTermination = { _ in request.cancel() }
    }
  }

  func stop() async {
    playing?.cancel()
    await player.stop()
  }

  private func play(_ text: String, into events: Continuation) async {
    playing?.cancel()
    await playing?.value
    guard !Task.isCancelled else {
      events.finish()
      return
    }
    if forwarder == nil {
      forwarder = Task { await forward() }
    }
    let task = Task { await speakLine(text, into: events) }
    playing = task
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }

  /// Returns once the player has reported the line finished, however it ended.
  private func speakLine(_ text: String, into events: Continuation) async {
    generation += 1
    let mine = generation
    let speaking = Task {
      do {
        try await player.speak(text, audio: audio(text))
      } catch {
        if generation == mine, line != nil { await player.stop() }
      }
    }
    await withTaskCancellationHandler {
      await withCheckedContinuation { done in line = Line(events: events, done: done) }
    } onCancel: {
      speaking.cancel()
    }
  }

  /// The player has one event stream for its whole life; each line gets the slice that belongs to it.
  private func forward() async {
    for await event in player.events {
      switch event {
      case .started:
        line?.events.yield(.started)
      case .finished:
        guard let line else { continue }
        line.events.yield(.finished)
        line.events.finish()
        line.done.resume()
        self.line = nil
      }
    }
  }
}
