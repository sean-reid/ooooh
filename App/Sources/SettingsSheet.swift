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
  private let appStore = AppStore.shared
  @State private var transcription: String?
  @State private var showsPaywall = false
  @State private var showsHistory = false
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    SettingsView(
      settings: settings, store: store, transcription: transcription, cloudSync: cloudSync,
      entitlement: billing.entitlement,
      subscribeAction: { showsPaywall = true },
      restore: { try await billing.restore() },
      openHistory: { showsHistory = true },
      onDone: { dismiss() }
    )
    .task { transcription = await Self.transcriptionLine(for: .current) }
    .onChange(of: settings.cloudSyncEnabled) { Task { await appStore.apply() } }
    .skySheet()
    .sheet(isPresented: $showsPaywall) {
      PaywallView(store: billing) { showsPaywall = false }.skySheet()
    }
    .sheet(isPresented: $showsHistory) {
      HistoryView(store: store).skySheet()
    }
  }

  private var cloudSync: CloudSyncState {
    CloudSyncState(
      configuration: appStore.running, accountAvailable: appStore.accountAvailable,
      syncEnabled: settings.cloudSyncEnabled)
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
