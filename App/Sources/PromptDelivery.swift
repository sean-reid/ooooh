import Foundation
import Notes
import OSLog
import Observation
import Transcription

/// Says the session's lines one at a time: the aboutToSpeak hold since the arm, the speaker for
/// the mode, the haptic and announcement in quiet mode, the echo filter's window in voice mode,
/// and the one path a line stops by.
@MainActor @Observable
final class PromptDelivery {
  /// What the controller knows and the delivery reads at the moment it matters.
  struct Session {
    var quiet: @MainActor () -> Bool
    var running: @MainActor () -> Bool
    var elapsed: @MainActor () -> TimeInterval
    /// True when the microphone can hear the line, on any route but headphones.
    var sealed: @MainActor () -> Bool
  }

  private(set) var lastPrompt: String?
  /// Every line delivered so far, with how it went; saved with the session at the end.
  private(set) var lines: [SpokenLine] = []
  private(set) var isSpeaking = false
  /// True from the arm until sound starts, or the arm is cancelled.
  private(set) var isPending = false
  var voice: any PromptSpeaking = SilentSpeaker()
  /// Hears every spoken line, so the microphone's take on it never reaches the loop.
  var echo: EchoFilter?
  var session = Session(quiet: { true }, running: { false }, elapsed: { 0 }, sealed: { true })

  private var pendingSince: Date?
  private var delivery: Task<Void, Never>?
  private var deliveringLine: UUID?
  private let hold: Duration
  private let haptic: @MainActor () -> Void
  private let announce: @MainActor (String) -> Void
  private static let log = Logger(subsystem: "com.seanreid.ooooh", category: "session")

  init(
    hold: Duration, haptic: @escaping @MainActor () -> Void,
    announce: @escaping @MainActor (String) -> Void
  ) {
    self.hold = hold
    self.haptic = haptic
    self.announce = announce
  }

  /// True while a line waits on the hold, on bytes, or plays.
  var isDelivering: Bool { delivery != nil }

  /// The loop armed a prompt; the hold counts from now.
  func arm() {
    isPending = true
    pendingSince = .now
  }

  /// Keeps the orb in aboutToSpeak for at least the configured hold since it armed, then speaks.
  /// The orb turns to speaking when sound starts, not when the request goes out.
  func deliver(_ text: String, kind: SpokenLine.Kind, at: TimeInterval, quietly: Bool = false) {
    if delivery != nil { cutDeliveringLine() }
    delivery?.cancel()
    delivery = nil
    guard !text.isEmpty else {
      isPending = false
      return
    }
    lastPrompt = text
    let line = SpokenLine(text: text, kind: kind, at: at, spoken: !(session.quiet() || quietly))
    lines.append(line)
    deliveringLine = line.id
    let since = pendingSince.map { Date.now.timeIntervalSince($0) } ?? 0
    let hold = hold - .seconds(since)
    delivery = Task {
      if hold > .zero { try? await Task.sleep(for: hold) }
      guard !Task.isCancelled, session.running() else { return }
      let quiet = session.quiet() || quietly
      if let index = lines.firstIndex(where: { $0.id == line.id }) {
        lines[index].spoken = !quiet
      }
      let speaker: any PromptSpeaking = quiet ? SilentSpeaker() : voice
      for await event in speaker.speak(text: text) {
        guard !Task.isCancelled else { return }
        switch event {
        case .started:
          isPending = false
          isSpeaking = true
          if quiet {
            haptic()
            announce(text)
          } else if let echo {
            echo.spoke(text, sealed: session.sealed())
            Self.log.info(
              """
              line started audioTime=\(echo.audioTime, format: .fixed(precision: 2), privacy: .public) \
              sessionTime=\(self.session.elapsed(), format: .fixed(precision: 2), privacy: .public)
              """)
          }
        case .finished:
          isSpeaking = false
          if !quiet { echo?.finishedSpeaking() }
        }
      }
      guard !Task.isCancelled else { return }
      isPending = false
      isSpeaking = false
      delivery = nil
      deliveringLine = nil
    }
  }

  /// The one path a line stops by, for End, speech in voice mode, and a cancelled arm. The orb
  /// leaves speaking at once, whether the request is still waiting on bytes or the line is playing.
  func cancel() async {
    isPending = false
    pendingSince = nil
    let wasSpeaking = isSpeaking
    isSpeaking = false
    guard let delivery else { return }
    cutDeliveringLine()
    self.delivery = nil
    delivery.cancel()
    Self.log.info("prompt cancelled speaking=\(wasSpeaking, privacy: .public)")
    await voice.stop()
    if wasSpeaking { echo?.finishedSpeaking() }
  }

  /// Sets or clears the bad mark on a line. False when the line is not one of this session's.
  func mark(_ lineID: UUID, bad: Bool) -> Bool {
    guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return false }
    lines[index].bad = bad
    return true
  }

  private func cutDeliveringLine() {
    guard let id = deliveringLine, let index = lines.firstIndex(where: { $0.id == id }) else {
      return
    }
    lines[index].cut = true
    deliveringLine = nil
  }
}
