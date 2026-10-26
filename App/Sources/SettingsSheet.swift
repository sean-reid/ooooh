import Billing
import Design
import Persistence
import Settings
import SwiftUI
import Transcription

/// Settings as the home screen presents it: the paywall and history open as sheets over it.
struct SettingsSheet: View {
  let store: SessionStore
  let billing: BillingStore
  @State private var settings = AppSettings()
  @State private var transcription: String?
  @State private var showsPaywall = false
  @State private var showsHistory = false
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    SettingsView(
      settings: settings, store: store, transcription: transcription,
      subscribeAction: { showsPaywall = true },
      openHistory: { showsHistory = true },
      onDone: { dismiss() }
    )
    .task { transcription = await Self.transcriptionLine(for: .current) }
    .skySheet()
    .sheet(isPresented: $showsPaywall) {
      PaywallView(store: billing) { showsPaywall = false }.skySheet()
    }
    .sheet(isPresented: $showsHistory) {
      HistoryView(store: store).skySheet()
    }
  }

  /// The engine Start would run, or that none takes the phone's language.
  static func transcriptionLine(for locale: Locale) async -> String {
    if let engine = await TranscriptionEngine.available(for: locale) { return engine.title }
    return "Not available for \(TranscriptionEngine.languageName(of: locale))"
  }
}

extension View {
  /// Every sheet in the app sits on the sky with a drag indicator.
  func skySheet() -> some View {
    presentationBackground(Palette.sky).presentationDragIndicator(.visible)
  }
}
