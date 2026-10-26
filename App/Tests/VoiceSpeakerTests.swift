import Foundation
import Testing

@testable import ooooh

@Suite struct VoiceSpeakerTests {
  @Test func buildsNoAudioEngineUntilItSpeaks() async {
    let speaker = VoiceSpeaker { _ in AsyncThrowingStream { $0.finish() } }
    #expect(await speaker.hasEngine == false)
  }
}
