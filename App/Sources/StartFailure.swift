import Foundation
import Transcription

/// What the home screen says when Start fails. The error itself goes to the console.
enum StartFailure: Equatable {
  case denied
  /// No engine on the phone transcribes the language, as against a model still to download.
  case unsupported(Locale)
  case noMicrophone
  case modelNeedsConnection
  case unavailable
  /// The start ran past its wait: a model install, the analyzer, or the Worker never answered.
  case timedOut

  /// On a simulator no engine takes any language, so the language is not the reason.
  init(_ error: any Error, simulator: Bool = isSimulator) {
    switch error {
    case CaptureError.microphoneDenied, CaptureError.speechDenied:
      self = .denied
    case SpeechAnalyzerError.unsupportedLocale(let locale),
      SpeechRecognizerError.onDeviceUnsupported(let locale):
      self = .unsupported(locale)
    case let missing as NoTranscriptionEngine:
      self = simulator ? .unavailable : .unsupported(missing.locale)
    case SpeechAnalyzerError.noMicrophoneInput, SpeechRecognizerError.noMicrophoneInput:
      self = .noMicrophone
    case SpeechAnalyzerError.downloadFailed:
      self = .modelNeedsConnection
    default:
      self = .unavailable
    }
  }

  var message: String {
    switch self {
    case .denied:
      "Allow the microphone in Settings to start."
    case .unsupported(let locale):
      "This phone can't transcribe \(TranscriptionEngine.languageName(of: locale)) on its own."
    case .noMicrophone:
      "The microphone isn't available right now."
    case .modelNeedsConnection:
      "Connect to the internet to download the speech model once."
    case .unavailable:
      "Listening isn't available on this device yet."
    case .timedOut:
      "Starting took too long. Try again."
    }
  }

  static var isSimulator: Bool {
    #if targetEnvironment(simulator)
      true
    #else
      false
    #endif
  }
}
