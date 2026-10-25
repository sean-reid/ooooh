import Foundation
import OSLog
import Transcription

/// What the home screen says when Start fails. The error itself goes to the console.
enum StartFailure {
  static let unavailable = "Listening isn't available on this device yet."
  static let denied = "Allow the microphone in Settings to start."

  private static let log = Logger(subsystem: "com.seanreid.ooooh", category: "session")

  static func message(for error: any Error) -> String {
    log.error("Start failed: \(String(describing: error), privacy: .public)")
    switch error {
    case CaptureError.microphoneDenied, CaptureError.speechDenied:
      return denied
    default:
      return unavailable
    }
  }
}
