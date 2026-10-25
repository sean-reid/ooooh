import AVFAudio
import Design
import Speech

enum CaptureError: LocalizedError {
  case microphoneDenied, speechDenied

  var errorDescription: String? {
    switch self {
    case .microphoneDenied: "Microphone access was denied. Allow it in Settings and try again."
    case .speechDenied: "Speech recognition was denied. Allow it in Settings and try again."
    }
  }

  var denial: CaptureDenial {
    switch self {
    case .microphoneDenied: .microphone
    case .speechDenied: .speechRecognition
    }
  }
}

/// Asks for the microphone and speech recognition, in that order.
enum CapturePermissions {
  static func request() async throws(CaptureError) {
    guard await AVAudioApplication.requestRecordPermission() else {
      throw CaptureError.microphoneDenied
    }
    let speech = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    guard speech == .authorized else { throw CaptureError.speechDenied }
  }
}
