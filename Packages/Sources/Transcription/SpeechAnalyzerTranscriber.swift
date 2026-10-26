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
  public actor SpeechAnalyzerTranscriber: LiveTranscriber {
    /// The SpeechAnalyzer modules that write text. DictationTranscriber runs on phones whose
    /// hardware SpeechTranscriber refuses.
    public enum Module: Sendable {
      case speechTranscriber
      case dictationTranscriber

      var engine: TranscriptionEngine {
        switch self {
        case .speechTranscriber: .speechTranscriber
        case .dictationTranscriber: .dictationTranscriber
        }
      }
    }

    public let locale: Locale
    public nonisolated let engine: TranscriptionEngine
    private let module: Module
    private let audioSink: (any AudioBufferSink)?
    private let stream: AsyncStream<TranscriptEvent>
    private let continuation: AsyncStream<TranscriptEvent>.Continuation
    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var activity = VoiceActivity()
    private var isRunning = false

    public init(
      module: Module = .speechTranscriber, locale: Locale = .current,
      audioSink: (any AudioBufferSink)? = nil
    ) {
      self.module = module
      self.engine = module.engine
      self.locale = locale
      self.audioSink = audioSink
      (stream, continuation) = AsyncStream.makeStream(of: TranscriptEvent.self)
    }

    public nonisolated func events() -> AsyncStream<TranscriptEvent> { stream }

    public func start() async throws {
      guard !isRunning else { return }
      let module = try await Self.makeModule(self.module, locale: locale)
      try await Self.ensureAssets(for: module.speechModule, locale: locale)
      guard
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(
          compatibleWith: [module.speechModule])
      else { throw SpeechAnalyzerError.noCompatibleAudioFormat }

      let (input, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
      let analyzer = SpeechAnalyzer(modules: [module.speechModule])
      try await analyzer.prepareToAnalyze(in: format)
      try await analyzer.start(inputSequence: input)
      self.analyzer = analyzer
      self.inputContinuation = inputContinuation
      resultsTask = Task { [weak self] in
        do {
          try await module.forEachSegment { segment in
            await self?.handle(segment)
          }
        } catch {
          await self?.fail(error)
        }
      }
      try installTap(format: format, into: inputContinuation)
      try audioEngine.start()
      isRunning = true
    }

    public func stop() async {
      guard isRunning else { return }
      isRunning = false
      audioEngine.inputNode.removeTap(onBus: 0)
      audioEngine.stop()
      inputContinuation?.finish()
      try? await analyzer?.finalizeAndFinishThroughEndOfInput()
      await resultsTask?.value
      finishStream()
    }

    private func handle(_ segment: Segment) {
      for event in activity.events(for: segment) {
        continuation.yield(event)
      }
    }

    private func fail(_ error: any Error) {
      guard isRunning else { return }
      isRunning = false
      audioEngine.inputNode.removeTap(onBus: 0)
      audioEngine.stop()
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
      let node = audioEngine.inputNode
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
      audioEngine.prepare()
    }

    private static func makeModule(_ module: Module, locale: Locale) async throws
      -> AnalyzerModule
    {
      switch module {
      case .speechTranscriber:
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
          throw SpeechAnalyzerError.unsupportedLocale(locale)
        }
        return .speech(
          SpeechTranscriber(
            locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]))
      case .dictationTranscriber:
        guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale)
        else { throw SpeechAnalyzerError.unsupportedLocale(locale) }
        return .dictation(dictationModule(locale: supported))
      }
    }

    /// Punctuation is opt-in here; SpeechTranscriber always writes it.
    static func dictationModule(locale: Locale) -> DictationTranscriber {
      DictationTranscriber(
        locale: locale, contentHints: [], transcriptionOptions: [.punctuation],
        reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
    }

    private static func ensureAssets(for module: any SpeechModule, locale: Locale) async throws {
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

  /// Both modules report the same way: volatile results replaced by a final one over the same
  /// audio range, with the range as a result attribute.
  private enum AnalyzerModule: Sendable {
    case speech(SpeechTranscriber)
    case dictation(DictationTranscriber)

    var speechModule: any SpeechModule {
      switch self {
      case .speech(let module): module
      case .dictation(let module): module
      }
    }

    func forEachSegment(_ body: (Segment) async -> Void) async throws {
      switch self {
      case .speech(let module):
        for try await result in module.results {
          await body(Segment(result, text: result.text))
        }
      case .dictation(let module):
        for try await result in module.results {
          await body(Segment(result, text: result.text))
        }
      }
    }
  }

  extension Segment {
    fileprivate init(_ result: some SpeechModuleResult, text: AttributedString) {
      self.init(text: String(text.characters), range: result.range, isFinal: result.isFinal)
    }
  }
#endif
