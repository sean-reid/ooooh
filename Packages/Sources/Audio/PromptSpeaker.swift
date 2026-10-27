#if os(iOS)
  import AVFAudio
  import Foundation
  import OSLog

  /// Plays one spoken prompt as its bytes arrive. `stop()` is barge-in: a request still waiting on bytes is cancelled, playback halts at once, and the rest of the stream is dropped.
  public actor PromptSpeaker {
    public enum Event: Equatable, Sendable {
      case started(text: String, at: Date)
      /// `rendered` is the player's own frame count at the moment playback ended or was cut.
      case finished(at: Date, rendered: AVAudioFramePosition)
    }

    public nonisolated let events: AsyncStream<Event>
    /// The line being spoken, for the caption. Nil between prompts.
    public private(set) var text: String?
    /// Frames of the current prompt the player has rendered, on the engine's clock. Nil while nothing plays.
    public var rendered: AVAudioFramePosition? {
      guard let player, let now = player.lastRenderTime else { return nil }
      return player.playerTime(forNodeTime: now)?.sampleTime
    }

    private let emit: AsyncStream<Event>.Continuation
    private let output: AVAudioFormat
    /// Built by the first line, so a session that never speaks never opens the audio server.
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var normalizer = LoudnessNormalizer()
    private var generation = 0
    private var scheduled = 0
    private var ended = false
    private var feeding: Task<Void, Error>?
    private var done: CheckedContinuation<Void, Never>?

    public init() {
      (events, emit) = AsyncStream.makeStream(of: Event.self)
      guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
        preconditionFailure("mono 44.1 kHz float is always available")
      }
      output = format
    }

    /// True once a line has built the engine graph.
    public var hasEngine: Bool { engine != nil }

    private static let log = Logger(subsystem: "com.seanreid.ooooh", category: "audio")
    private var bytes = 0

    /// The gain the current or most recent line settled on, in dB.
    public var lineGainDB: Float { normalizer.gainDB }

    /// Decodes and plays `audio`. Returns once the last buffer has played, `stop()` cut it off, or the calling task was cancelled.
    public func speak(_ text: String, audio: AsyncThrowingStream<Data, Error>) async throws {
      stop()
      generation += 1
      let mine = generation
      self.text = text
      scheduled = 0
      ended = false
      bytes = 0
      Self.log.info("speak begins chars=\(text.count, privacy: .public)")
      let parser = try AudioStreamParser()
      let decoder = SpeechDecoder(output: output)
      normalizer = LoudnessNormalizer()
      let (engine, player) = graph()
      let feed = Task {
        var bytes = audio.makeAsyncIterator()
        while let chunk = try await bytes.next() {
          guard mine == generation else {
            // The stream learns of a cancel only inside next(); a chunk that arrived with one needs one more read.
            if Task.isCancelled { _ = try? await bytes.next() }
            return
          }
          self.bytes += chunk.count
          for packets in try parser.parse(chunk) {
            guard let pcm = try decoder.decode(packets) else { continue }
            normalizer.apply(to: pcm)
            schedule(pcm, on: player, generation: mine)
            if scheduled == 1 {
              try engine.start()
              player.play()
              Self.log.info(
                "speak started bytes=\(self.bytes, privacy: .public) format=\(pcm.format.sampleRate, privacy: .public)Hz output=\(engine.outputNode.outputFormat(forBus: 0).sampleRate, privacy: .public)Hz"
              )
              emit.yield(.started(text: text, at: Date()))
            }
          }
        }
      }
      feeding = feed
      try await withTaskCancellationHandler {
        do {
          try await feed.value
        } catch {
          Self.log.error(
            "speak failed bytes=\(self.bytes, privacy: .public) error=\(String(describing: error), privacy: .public)"
          )
          if mine == generation { finish() }
          throw error
        }
        guard mine == generation else { return }
        ended = true
        if scheduled == 0 {
          Self.log.error("speak decoded nothing bytes=\(self.bytes, privacy: .public)")
          finish()
          return
        }
        await withCheckedContinuation { done = $0 }
      } onCancel: {
        Task { await self.cut(mine) }
      }
    }

    /// Barge-in. Safe to call when nothing is playing.
    public func stop() {
      guard text != nil else { return }
      Self.log.info("speak cut rendered=\(self.rendered ?? 0, privacy: .public)")
      finish()
    }

    private func cut(_ generation: Int) {
      if generation == self.generation { finish() }
    }

    private func graph() -> (AVAudioEngine, AVAudioPlayerNode) {
      if let engine, let player { return (engine, player) }
      let engine = AVAudioEngine()
      let player = AVAudioPlayerNode()
      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: output)
      engine.prepare()
      self.engine = engine
      self.player = player
      return (engine, player)
    }

    private func schedule(
      _ pcm: AVAudioPCMBuffer, on player: AVAudioPlayerNode, generation mine: Int
    ) {
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
      feeding?.cancel()
      feeding = nil
      let rendered = rendered ?? 0
      player?.stop()
      engine?.stop()
      text = nil
      Self.log.info(
        "speak finished rendered=\(rendered, privacy: .public) gain=\(self.normalizer.gainDB, format: .fixed(precision: 1), privacy: .public)dB"
      )
      emit.yield(.finished(at: Date(), rendered: rendered))
      done?.resume()
      done = nil
    }
  }
#endif
