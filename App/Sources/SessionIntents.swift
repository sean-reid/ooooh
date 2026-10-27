import AppIntents

struct StartSessionIntent: AppIntent {
  static let title: LocalizedStringResource = "Start a session"
  static let description = IntentDescription("Opens ooooh and starts listening.")
  static let openAppWhenRun = true

  @MainActor func perform() async throws -> some IntentResult {
    SessionHost.shared.start()
    return .result()
  }
}

struct EndSessionIntent: AppIntent {
  static let title: LocalizedStringResource = "End the session"
  static let description = IntentDescription("Ends the session ooooh is listening to.")

  @MainActor func perform() async throws -> some IntentResult {
    await SessionHost.shared.end()
    return .result()
  }
}

/// Siri phrases, the Shortcuts app, and the Action button all read these.
struct OooohShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartSessionIntent(),
      phrases: [
        "Start \(.applicationName)",
        "Start a \(.applicationName) session",
        "Think aloud with \(.applicationName)",
      ],
      shortTitle: "Start a session",
      systemImageName: "waveform")
    AppShortcut(
      intent: EndSessionIntent(),
      phrases: [
        "End \(.applicationName)",
        "End the \(.applicationName) session",
        "Stop \(.applicationName)",
      ],
      shortTitle: "End the session",
      systemImageName: "stop.circle")
  }
}
