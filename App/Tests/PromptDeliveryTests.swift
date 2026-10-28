import Foundation
import Notes
import TestSupport
import Testing

@testable import ooooh

/// The delivery on its own, over a speaker that records every call: the hold since the arm, what
/// each mode does when sound starts, the cut on cancel, and the marks on the lines it said.
@MainActor
@Suite struct PromptDeliveryTests {
  final class Counter { var count = 0 }
  final class Lines { var lines: [String] = [] }

  /// A delivery in a running session, quiet or in voice, with a 200 ms hold.
  func delivery(
    quiet: Bool, speaker: any PromptSpeaking, haptics: Counter = Counter(),
    announcements: Lines = Lines()
  ) -> PromptDelivery {
    let delivery = PromptDelivery(
      hold: .milliseconds(200), haptic: { haptics.count += 1 },
      announce: { announcements.lines.append($0) })
    delivery.voice = speaker
    delivery.session = .init(
      quiet: { quiet }, running: { true }, elapsed: { 4.2 }, sealed: { false })
    return delivery
  }

  @Test func aVoiceLineWaitsOutTheHoldThenSpeaksAndIsCutByCancel() async {
    let speaker = SessionControllerTests.Recorder()
    let haptics = Counter()
    let delivery = delivery(quiet: false, speaker: speaker, haptics: haptics)

    delivery.arm()
    #expect(delivery.isPending)
    let armed = ContinuousClock.now
    delivery.deliver("What sits underneath that?", kind: .intervention(.deepen), at: 16.5)
    #expect(delivery.isDelivering)
    #expect(delivery.lastPrompt == "What sits underneath that?")
    #expect(delivery.lines.map(\.spoken) == [true])
    #expect(!delivery.isSpeaking)
    await wait { delivery.isSpeaking }
    #expect(ContinuousClock.now - armed >= .milliseconds(190))
    #expect(!delivery.isPending)
    #expect(speaker.calls == ["speak What sits underneath that?"])
    #expect(haptics.count == 0)

    await delivery.cancel()
    #expect(!delivery.isSpeaking)
    #expect(!delivery.isDelivering)
    #expect(delivery.lines.map(\.cut) == [true])
    #expect(speaker.calls == ["speak What sits underneath that?", "stop"])
  }

  @Test func aQuietLineGoesThroughTheHapticAndTheAnnouncement() async {
    let speaker = SessionControllerTests.Recorder()
    let haptics = Counter()
    let announcements = Lines()
    let delivery = delivery(
      quiet: true, speaker: speaker, haptics: haptics, announcements: announcements)

    delivery.arm()
    delivery.deliver("Done for now?", kind: .finishedQuestion, at: 25.5)
    #expect(delivery.lines.map(\.spoken) == [false])
    await wait { delivery.isSpeaking }
    #expect(haptics.count == 1)
    #expect(announcements.lines == ["Done for now?"])
    #expect(speaker.calls.isEmpty)
    await wait { !delivery.isDelivering }
    #expect(!delivery.isSpeaking)
    #expect(delivery.lines.map(\.cut) == [false])
  }

  @Test func anEmptyLineOnlyClearsTheArm() async {
    let speaker = SessionControllerTests.Recorder()
    let delivery = delivery(quiet: false, speaker: speaker)
    delivery.arm()
    delivery.deliver("", kind: .intervention(.deepen), at: 1)
    #expect(!delivery.isPending)
    #expect(!delivery.isDelivering)
    #expect(delivery.lines.isEmpty)
    #expect(delivery.lastPrompt == nil)

    await delivery.cancel()
    #expect(speaker.calls.isEmpty)
  }

  @Test func aSecondLineCutsTheFirst() async {
    let speaker = SessionControllerTests.Recorder()
    let delivery = delivery(quiet: false, speaker: speaker)
    delivery.deliver("What sits underneath that?", kind: .intervention(.deepen), at: 1)
    await wait { delivery.isSpeaking }
    delivery.deliver("What would make that wrong?", kind: .intervention(.challenge), at: 2)
    #expect(delivery.lines.map(\.cut) == [true, false])
    #expect(delivery.lastPrompt == "What would make that wrong?")
    await delivery.cancel()
  }

  @Test func marksLandOnTheLineSaidAndOnNoOther() async {
    let delivery = delivery(quiet: true, speaker: SessionControllerTests.Recorder())
    delivery.deliver("What sits underneath that?", kind: .intervention(.deepen), at: 1)
    let line = delivery.lines[0]
    #expect(delivery.mark(line.id, bad: true))
    #expect(delivery.lines.map(\.bad) == [true])
    #expect(delivery.mark(line.id, bad: false))
    #expect(delivery.lines.map(\.bad) == [false])
    #expect(!delivery.mark(UUID(), bad: true))
    await delivery.cancel()
  }
}
