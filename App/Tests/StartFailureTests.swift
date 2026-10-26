import Foundation
import Testing
import Transcription

@testable import ooooh

@Suite struct StartFailureTests {
  let english = Locale(identifier: "en_US")

  @Test func aDenialSaysToAllowTheMicrophone() {
    #expect(StartFailure(CaptureError.microphoneDenied) == .denied)
    #expect(StartFailure(CaptureError.speechDenied) == .denied)
    #expect(StartFailure.denied.message == "Allow the microphone in Settings to start.")
  }

  @Test func everyEngineNamesTheLanguageItCannotTake() {
    #expect(StartFailure(SpeechAnalyzerError.unsupportedLocale(english)) == .unsupported(english))
    #expect(
      StartFailure(SpeechRecognizerError.onDeviceUnsupported(english)) == .unsupported(english))
    #expect(
      StartFailure(NoTranscriptionEngine(locale: english), simulator: false)
        == .unsupported(english))
    #expect(
      StartFailure.unsupported(english).message
        == "This phone can't transcribe English on its own.")
  }

  @Test func theSimulatorKeepsTheCatchAllWhenNoEngineTakesTheLanguage() {
    #expect(StartFailure(NoTranscriptionEngine(locale: english), simulator: true) == .unavailable)
  }

  @Test func noInputFromEitherEngineSaysTheMicrophoneIsNotAvailable() {
    #expect(StartFailure(SpeechAnalyzerError.noMicrophoneInput) == .noMicrophone)
    #expect(StartFailure(SpeechRecognizerError.noMicrophoneInput) == .noMicrophone)
    #expect(StartFailure.noMicrophone.message == "The microphone isn't available right now.")
  }

  @Test func aFailedDownloadAsksForAConnectionOnce() {
    #expect(StartFailure(SpeechAnalyzerError.downloadFailed(english)) == .modelNeedsConnection)
    #expect(
      StartFailure.modelNeedsConnection.message
        == "Connect to the internet to download the speech model once.")
  }

  @Test func everythingElseKeepsTheCatchAll() {
    #expect(StartFailure(SpeechAnalyzerError.assetsNotInstalled(english)) == .unavailable)
    #expect(StartFailure(SpeechAnalyzerError.noCompatibleAudioFormat) == .unavailable)
    #expect(StartFailure(SpeechRecognizerError.unavailable) == .unavailable)
    #expect(StartFailure(CocoaError(.fileNoSuchFile)) == .unavailable)
    #expect(StartFailure.unavailable.message == "Listening isn't available on this device yet.")
  }

  @Test func eachCaseReadsDifferently() {
    let failures: [StartFailure] = [
      .denied, .unsupported(english), .noMicrophone, .modelNeedsConnection, .unavailable,
    ]
    let messages = failures.map(\.message)
    #expect(Set(messages).count == messages.count)
  }
}
