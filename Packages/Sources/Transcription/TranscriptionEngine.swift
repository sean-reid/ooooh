import Foundation

/// The engines that turn the microphone into text, in the order the app tries them.
public enum TranscriptionEngine: String, CaseIterable, Sendable {
  case speechTranscriber
  case dictationTranscriber
  case speechRecognizer

  /// The engine as Settings names it.
  public var title: String {
    switch self {
    case .speechTranscriber: "On-device transcription"
    case .dictationTranscriber: "On-device dictation"
    case .speechRecognizer: "On-device speech recognition"
    }
  }

  /// What the frameworks answer for one locale on this phone.
  public struct Availability: Equatable, Sendable {
    public var speechTranscriberAvailable: Bool
    public var speechTranscriberSupportsLocale: Bool
    public var dictationTranscriberSupportsLocale: Bool
    public var dictationTranscriberAssetsSupported: Bool
    public var recognizerSupportsOnDevice: Bool

    public init(
      speechTranscriberAvailable: Bool = false, speechTranscriberSupportsLocale: Bool = false,
      dictationTranscriberSupportsLocale: Bool = false,
      dictationTranscriberAssetsSupported: Bool = false, recognizerSupportsOnDevice: Bool = false
    ) {
      self.speechTranscriberAvailable = speechTranscriberAvailable
      self.speechTranscriberSupportsLocale = speechTranscriberSupportsLocale
      self.dictationTranscriberSupportsLocale = dictationTranscriberSupportsLocale
      self.dictationTranscriberAssetsSupported = dictationTranscriberAssetsSupported
      self.recognizerSupportsOnDevice = recognizerSupportsOnDevice
    }
  }

  /// SpeechTranscriber when the phone has it, DictationTranscriber when only that SpeechAnalyzer
  /// module takes the locale, SFSpeechRecognizer on the phone last; nil when none does.
  public static func select(_ availability: Availability) -> TranscriptionEngine? {
    if availability.speechTranscriberAvailable, availability.speechTranscriberSupportsLocale {
      return .speechTranscriber
    }
    if availability.dictationTranscriberSupportsLocale,
      availability.dictationTranscriberAssetsSupported
    {
      return .dictationTranscriber
    }
    if availability.recognizerSupportsOnDevice { return .speechRecognizer }
    return nil
  }

  /// "English" for en_US, in the phone's language.
  public static func languageName(of locale: Locale) -> String {
    let code = locale.language.languageCode?.identifier ?? locale.identifier
    return Locale.current.localizedString(forLanguageCode: code) ?? code
  }
}

/// No engine on this phone takes the locale.
public struct NoTranscriptionEngine: Error, Equatable {
  public let locale: Locale

  public init(locale: Locale) { self.locale = locale }
}

/// A transcriber on the microphone that reports which engine it runs.
public protocol LiveTranscriber: Transcriber {
  var engine: TranscriptionEngine { get }
  /// The fraction of the speech model downloaded while `start()` installs it. Finishes with
  /// `start()`, and yields nothing when the model is on the phone.
  func downloadProgress() -> AsyncStream<Double>
  func start() async throws
}

#if os(iOS)
  import Speech

  extension TranscriptionEngine {
    public static func availability(for locale: Locale) async -> Availability {
      var availability = Availability()
      availability.speechTranscriberAvailable = SpeechTranscriber.isAvailable
      availability.speechTranscriberSupportsLocale =
        await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil
      var assets = "noLocale"
      if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
        availability.dictationTranscriberSupportsLocale = true
        let module = SpeechAnalyzerTranscriber.dictationModule(locale: supported)
        let status = await AssetInventory.status(forModules: [module])
        assets = String(describing: status)
        availability.dictationTranscriberAssetsSupported = status != .unsupported
      }
      let recognizer = SFSpeechRecognizer(locale: locale)
      availability.recognizerSupportsOnDevice = recognizer?.supportsOnDeviceRecognition ?? false
      transcriptionLog.info(
        """
        probe locale=\(locale.identifier, privacy: .public) \
        speechTranscriber available=\(availability.speechTranscriberAvailable, privacy: .public) \
        locale=\(availability.speechTranscriberSupportsLocale, privacy: .public) \
        dictation locale=\(availability.dictationTranscriberSupportsLocale, privacy: .public) \
        assets=\(assets, privacy: .public) \
        recognizer onDevice=\(availability.recognizerSupportsOnDevice, privacy: .public) \
        available=\(recognizer?.isAvailable ?? false, privacy: .public)
        """)
      return availability
    }

    public static func available(for locale: Locale) async -> TranscriptionEngine? {
      let engine = select(await availability(for: locale))
      transcriptionLog.info("engine=\(engine?.rawValue ?? "none", privacy: .public)")
      return engine
    }

    public func makeTranscriber(locale: Locale, audioSink: (any AudioBufferSink)?)
      -> any LiveTranscriber
    {
      switch self {
      case .speechTranscriber:
        SpeechAnalyzerTranscriber(module: .speechTranscriber, locale: locale, audioSink: audioSink)
      case .dictationTranscriber:
        SpeechAnalyzerTranscriber(
          module: .dictationTranscriber, locale: locale, audioSink: audioSink)
      case .speechRecognizer:
        SpeechRecognizerTranscriber(locale: locale, audioSink: audioSink)
      }
    }
  }
#endif
