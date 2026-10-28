import Testing

@testable import Audio

#if os(iOS)
  import AVFAudio

  /// The route decides who may cut a line: only an output whose microphone travels with it.
  @Suite struct AudioRouteTests {
    @Test func aBluetoothSpeakerLeavesThePhonesMicrophoneListening() {
      let route = AudioRoute(outputPortTypes: [.bluetoothA2DP], inputPortTypes: [.builtInMic])
      #expect(route == .other)
    }

    @Test func aBluetoothHeadsetBringsItsOwnMicrophone() {
      let route = AudioRoute(outputPortTypes: [.bluetoothA2DP], inputPortTypes: [.bluetoothHFP])
      #expect(route == .headphones)
      #expect(
        AudioRoute(outputPortTypes: [.bluetoothHFP], inputPortTypes: [.bluetoothHFP]) == .headphones
      )
    }

    @Test func wiredHeadphonesStayHeadphonesWhateverTheMicrophone() {
      #expect(
        AudioRoute(outputPortTypes: [.headphones], inputPortTypes: [.headsetMic]) == .headphones)
      #expect(
        AudioRoute(outputPortTypes: [.headphones], inputPortTypes: [.builtInMic]) == .headphones)
    }

    @Test func theCarAndTheSpeakerKeepTheirRoutes() {
      #expect(AudioRoute(outputPortTypes: [.carAudio], inputPortTypes: [.builtInMic]) == .car)
      #expect(
        AudioRoute(outputPortTypes: [.builtInSpeaker], inputPortTypes: [.builtInMic]) == .speaker)
      #expect(AudioRoute(outputPortTypes: [.airPlay]) == .other)
    }
  }
#endif
