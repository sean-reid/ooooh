import Foundation
import Testing

@testable import Transcription

@Suite struct TranscriptionEngineTests {
  typealias Availability = TranscriptionEngine.Availability

  @Test func speechTranscriberWinsWhenItIsAvailableAndTakesTheLocale() {
    let everything = Availability(
      speechTranscriberAvailable: true, speechTranscriberSupportsLocale: true,
      dictationTranscriberSupportsLocale: true, dictationTranscriberAssetsSupported: true,
      recognizerSupportsOnDevice: true)
    #expect(TranscriptionEngine.select(everything) == .speechTranscriber)
  }

  @Test func speechTranscriberNeedsBothTheHardwareAndTheLocale() {
    let hardwareOnly = Availability(
      speechTranscriberAvailable: true, speechTranscriberSupportsLocale: false,
      recognizerSupportsOnDevice: true)
    #expect(TranscriptionEngine.select(hardwareOnly) == .speechRecognizer)
    let localeOnly = Availability(
      speechTranscriberAvailable: false, speechTranscriberSupportsLocale: true,
      recognizerSupportsOnDevice: true)
    #expect(TranscriptionEngine.select(localeOnly) == .speechRecognizer)
  }

  @Test func dictationTranscriberComesNextWhenItsLocaleAndAssetsAreSupported() {
    let dictation = Availability(
      dictationTranscriberSupportsLocale: true, dictationTranscriberAssetsSupported: true,
      recognizerSupportsOnDevice: true)
    #expect(TranscriptionEngine.select(dictation) == .dictationTranscriber)
  }

  @Test func dictationTranscriberWithUnsupportedAssetsFallsThrough() {
    let localeOnly = Availability(
      dictationTranscriberSupportsLocale: true, dictationTranscriberAssetsSupported: false,
      recognizerSupportsOnDevice: true)
    #expect(TranscriptionEngine.select(localeOnly) == .speechRecognizer)
  }

  @Test func theRecognizerIsLastAndNothingIsNil() {
    #expect(
      TranscriptionEngine.select(Availability(recognizerSupportsOnDevice: true))
        == .speechRecognizer)
    #expect(TranscriptionEngine.select(Availability()) == nil)
  }

  @Test func titlesReadAsSettingsLines() {
    #expect(TranscriptionEngine.speechTranscriber.title == "On-device transcription")
    #expect(TranscriptionEngine.dictationTranscriber.title == "On-device dictation")
    #expect(TranscriptionEngine.speechRecognizer.title == "On-device speech recognition")
  }

  @Test func languageNameDropsTheRegion() {
    let name = TranscriptionEngine.languageName(of: Locale(identifier: "en_US"))
    #expect(name == Locale.current.localizedString(forLanguageCode: "en"))
    #expect(!name.contains("US"))
  }
}
