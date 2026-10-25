import Testing

@testable import Audio

@Suite struct SpeechPolicyTests {
  @Test func speakerIsQuietEverythingElseSpeaks() {
    #expect(!shouldSpeak(route: .speaker))
    #expect(shouldSpeak(route: .headphones))
    #expect(shouldSpeak(route: .car))
    #expect(shouldSpeak(route: .other))
  }
}
