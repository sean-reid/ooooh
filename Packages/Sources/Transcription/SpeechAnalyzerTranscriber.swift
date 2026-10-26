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
    private var configurationWatch: Task<Void, Never>?
    private var activity = VoiceActivity()
    private var isRunning = false
    private var startedAt: ContinuousClock.Instant?
    private var heardResult = false
    private var pauseFinalize: Task<Void, Never>?
    /// Seconds without a new volatile result before the dictation module is asked to finalize;
    /// SpeechTranscriber finalizes on its own, DictationTranscriber only when told.
    static let dictationPause: TimeInterval = 1

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
      do {
        try await begin()
      } catch {
        log("start failed error=\(String(describing: error))", error: true)
        throw error
      }
    }

    private func begin() async throws {
      let module = try await Self.makeModule(self.module, locale: locale)
      try await Self.ensureAssets(for: module.speechModule, locale: locale, engine: engine)
      guard
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(
          compatibleWith: [module.speechModule])
      else { throw SpeechAnalyzerError.noCompatibleAudioFormat }
      log("analyzer format=\(format.logDescription)")

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
      startedAt = .now
      isRunning = true
      configurationWatch = watchConfiguration()
      log("started")
    }

    public func stop() async {
      guard isRunning else { return }
      isRunning = false
      pauseFinalize?.cancel()
      configurationWatch?.cancel()
      audioEngine.inputNode.removeTap(onBus: 0)
      audioEngine.stop()
      inputContinuation?.finish()
      try? await analyzer?.finalizeAndFinishThroughEndOfInput()
      await resultsTask?.value
      finishStream()
    }

    private func handle(_ segment: Segment) {
      if !heardResult, let startedAt {
        heardResult = true
        let latency = startedAt.duration(to: .now).wholeMilliseconds
        log("first result latencyMs=\(latency) final=\(segment.isFinal)")
      }
      for event in activity.events(for: segment) {
        continuation.yield(event)
      }
      guard module == .dictationTranscriber else { return }
      pauseFinalize?.cancel()
      if !segment.isFinal { pauseFinalize = scheduleFinalize() }
    }

    /// Finalizes everything heard so far once no result has followed for `dictationPause`.
    private func scheduleFinalize() -> Task<Void, Never> {
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(Self.dictationPause))
        guard !Task.isCancelled else { return }
        await self?.finalizePause()
      }
    }

    private func finalizePause() async {
      guard isRunning, let analyzer else { return }
      do {
        try await analyzer.finalize(through: nil)
        log("finalized on pause")
      } catch {
        log("finalize on pause failed error=\(String(describing: error))", error: true)
      }
    }

    private func fail(_ error: any Error) {
      log("results failed error=\(String(describing: error))", error: true)
      guard isRunning else { return }
      isRunning = false
      pauseFinalize?.cancel()
      configurationWatch?.cancel()
      audioEngine.inputNode.removeTap(onBus: 0)
      audioEngine.stop()
      inputContinuation?.finish()
      finishStream()
    }

    /// The engine stops itself when the hardware format changes under it; that is the one way a
    /// started tap goes quiet without an error.
    private func watchConfiguration() -> Task<Void, Never> {
      Task { [weak self] in
        let changes = NotificationCenter.default.notifications(
          named: .AVAudioEngineConfigurationChange)
        for await _ in changes {
          await self?.logConfigurationChange()
        }
      }
    }

    private func logConfigurationChange() {
      log("engine configuration changed running=\(audioEngine.isRunning)")
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
      log("input format=\(inputFormat.logDescription)")
      guard inputFormat.sampleRate > 0 else { throw SpeechAnalyzerError.noMicrophoneInput }
      guard let converter = BufferConverter(from: inputFormat, to: format) else {
        throw SpeechAnalyzerError.audioConversionUnavailable
      }
      let sink = audioSink
      let monitor = TapMonitor(engine: engine)
      node.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
        monitor.observe(buffer)
        sink?.write(buffer)
        if let converted = converter.convert(buffer) {
          input.yield(AnalyzerInput(buffer: converted))
        }
      }
      audioEngine.prepare()
    }

    private nonisolated func log(_ message: String, error: Bool = false) {
      Self.log(message, engine: engine, error: error)
    }

    private static func log(_ message: String, engine: TranscriptionEngine, error: Bool = false) {
      if error {
        transcriptionLog.error(
          "\(message, privacy: .public) engine=\(engine.rawValue, privacy: .public)")
      } else {
        transcriptionLog.info(
          "\(message, privacy: .public) engine=\(engine.rawValue, privacy: .public)")
      }
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

    private static func ensureAssets(
      for module: any SpeechModule, locale: Locale, engine: TranscriptionEngine
    ) async throws {
      let status = await AssetInventory.status(forModules: [module])
      log("assets before=\(String(describing: status))", engine: engine)
      if status == .installed { return }
      if status == .unsupported { throw SpeechAnalyzerError.unsupportedLocale(locale) }
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
        try await request.downloadAndInstall()
      }
      let after = await AssetInventory.status(forModules: [module])
      log("assets after=\(String(describing: after))", engine: engine)
      guard after == .installed else {
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
