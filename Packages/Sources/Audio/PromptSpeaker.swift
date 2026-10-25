#if os(iOS)
  import AVFAudio
  import Foundation

  /// Plays one spoken prompt as its bytes arrive. `stop()` is barge-in: playback halts at once and the rest of the stream is dropped.
  public actor PromptSpeaker {
    public enum Event: Equatable, Sendable {
      case started(text: String, at: Date)
      case finished(at: Date)
    }

    public nonisolated let events: AsyncStream<Event>
    /// The line being spoken, for the caption. Nil between prompts.
    public private(set) var text: String?

    private let emit: AsyncStream<Event>.Continuation
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let output: AVAudioFormat
    private var generation = 0
    private var scheduled = 0
    private var ended = false
    private var done: CheckedContinuation<Void, Never>?

    public init() {
      (events, emit) = AsyncStream.makeStream(of: Event.self)
      guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
        preconditionFailure("mono 44.1 kHz float is always available")
      }
      output = format
      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: output)
      engine.prepare()
    }

    /// Decodes and plays `audio`. Returns once the last buffer has played or `stop()` cut it off.
    public func speak(_ text: String, audio: AsyncThrowingStream<Data, Error>) async throws {
      stop()
      generation += 1
      let mine = generation
      self.text = text
      scheduled = 0
      ended = false
      let parser = try AudioStreamParser()
      let decoder = SpeechDecoder(output: output)
      do {
        for try await chunk in audio {
          guard mine == generation else { return }
          for packets in try parser.parse(chunk) {
            guard let pcm = try decoder.decode(packets) else { continue }
            schedule(pcm, generation: mine)
            if scheduled == 1 {
              try engine.start()
              player.play()
              emit.yield(.started(text: text, at: Date()))
            }
          }
        }
      } catch {
        if mine == generation { finish() }
        throw error
      }
      guard mine == generation else { return }
      ended = true
      if scheduled == 0 {
        finish()
        return
      }
      await withCheckedContinuation { done = $0 }
    }

    /// Barge-in. Safe to call when nothing is playing.
    public func stop() {
      if text != nil { finish() }
    }

    private func schedule(_ pcm: AVAudioPCMBuffer, generation mine: Int) {
      scheduled += 1
      player.scheduleBuffer(pcm, completionCallbackType: .dataPlayedBack) { _ in
        Task { await self.played(generation: mine) }
      }
    }

    private func played(generation mine: Int) {
      guard mine == generation else { return }
      scheduled -= 1
      if ended && scheduled == 0 { finish() }
    }

    private func finish() {
      generation += 1
      player.stop()
      engine.stop()
      text = nil
      emit.yield(.finished(at: Date()))
      done?.resume()
      done = nil
    }
  }
#endif
