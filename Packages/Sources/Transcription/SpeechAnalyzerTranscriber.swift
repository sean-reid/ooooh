#if os(iOS)
  import AVFAudio
  import Foundation
  import Speech

  public enum SpeechAnalyzerError: Error, Equatable, LocalizedError {
    case unsupportedLocale(Locale)
    case assetsNotInstalled(Locale)
    case noCompatibleAudioFormat
    case noMicrophoneInput
    case audioConversionUnavailable

    public var errorDescription: String? {
      switch self {
      case .unsupportedLocale(let locale):
        return "On-device transcription does not support \(locale.identifier)."
      case .assetsNotInstalled(let locale):
        return "The speech model for \(locale.identifier) is not installed on this phone."
      case .noCompatibleAudioFormat:
        return "The transcriber offered no audio format this phone can produce."
      case .noMicrophoneInput:
        return "No microphone input. Activate the audio session before starting."
      case .audioConversionUnavailable:
        return "The microphone format cannot be converted for the transcriber."
      }
    }
  }

  /// Live transcription from the microphone through SpeechAnalyzer. Segment times are seconds since `start()`.
  public actor SpeechAnalyzerTranscriber: Transcriber {
    public let locale: Locale
    private let audioSink: (any AudioBufferSink)?
    private let stream: AsyncStream<TranscriptEvent>
    private let continuation: AsyncStream<TranscriptEvent>.Continuation
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var activity = VoiceActivity()
    private var isRunning = false

    public init(locale: Locale = .current, audioSink: (any AudioBufferSink)? = nil) {
      self.locale = locale
      self.audioSink = audioSink
      (stream, continuation) = AsyncStream.makeStream(of: TranscriptEvent.self)
    }

    public nonisolated func events() -> AsyncStream<TranscriptEvent> { stream }

    public func start() async throws {
      guard !isRunning else { return }
      let module = try await Self.makeModule(locale: locale)
      try await Self.ensureAssets(for: module, locale: locale)
      guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
      else { throw SpeechAnalyzerError.noCompatibleAudioFormat }

      let (input, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
      let analyzer = SpeechAnalyzer(modules: [module])
      try await analyzer.prepareToAnalyze(in: format)
      try await analyzer.start(inputSequence: input)
      self.analyzer = analyzer
      self.inputContinuation = inputContinuation
      resultsTask = Task { [weak self] in
        do {
          for try await result in module.results {
            await self?.handle(result)
          }
        } catch {
          await self?.fail(error)
        }
      }
      try installTap(format: format, into: inputContinuation)
      try engine.start()
      isRunning = true
    }

    public func stop() async {
      guard isRunning else { return }
      isRunning = false
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
      inputContinuation?.finish()
      try? await analyzer?.finalizeAndFinishThroughEndOfInput()
      await resultsTask?.value
      finishStream()
    }

    private func handle(_ result: SpeechTranscriber.Result) {
      let segment = Segment(
        text: String(result.text.characters), range: result.range, isFinal: result.isFinal)
      for event in activity.events(for: segment) {
        continuation.yield(event)
      }
    }

    private func fail(_ error: any Error) {
      guard isRunning else { return }
      isRunning = false
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
      inputContinuation?.finish()
      finishStream()
    }

    private func finishStream() {
      for event in activity.close() {
        continuation.yield(event)
      }
      continuation.yield(.ended)
      continuation.finish()
    }

    private func installTap(
      format: AVAudioFormat, into input: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
      let node = engine.inputNode
      let inputFormat = node.outputFormat(forBus: 0)
      guard inputFormat.sampleRate > 0 else { throw SpeechAnalyzerError.noMicrophoneInput }
      guard let converter = BufferConverter(from: inputFormat, to: format) else {
        throw SpeechAnalyzerError.audioConversionUnavailable
      }
      let sink = audioSink
      node.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
        sink?.write(buffer)
        if let converted = converter.convert(buffer) {
          input.yield(AnalyzerInput(buffer: converted))
        }
      }
      engine.prepare()
    }

    private static func makeModule(locale: Locale) async throws -> SpeechTranscriber {
      guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
        throw SpeechAnalyzerError.unsupportedLocale(locale)
      }
      return SpeechTranscriber(
        locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults],
        attributeOptions: [.audioTimeRange])
    }

    private static func ensureAssets(for module: SpeechTranscriber, locale: Locale) async throws {
      let status = await AssetInventory.status(forModules: [module])
      if status == .installed { return }
      if status == .unsupported { throw SpeechAnalyzerError.unsupportedLocale(locale) }
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
        try await request.downloadAndInstall()
      }
      guard await AssetInventory.status(forModules: [module]) == .installed else {
        throw SpeechAnalyzerError.assetsNotInstalled(locale)
      }
    }
  }
#endif
