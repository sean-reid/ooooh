import Billing
import Design
import Persistence
import SwiftUI

#if os(iOS)
  import StoreKit
#endif

/// The settings screen: listener switches, subscription, data controls, privacy, about.
public struct SettingsView: View {
  @Bindable var settings: AppSettings
  var store: SessionStore
  var version: String
  var transcription: String?
  var cloudSync: CloudSyncState
  var entitlement: Entitlement
  var subscribeAction: () -> Void
  var restore: () async throws -> Entitlement
  var openHistory: () -> Void
  var onDone: (() -> Void)?
  /// ImageRenderer draws a NavigationStack and a ScrollView empty, so snapshots render the
  /// content flat.
  var scrolls = true
  /// The day the renewal date is compared against, fixed in snapshots.
  var now = Date.now
  @State private var sessionCount: Int?
  @State private var confirmingDelete = false
  @State private var deleteFailure: String?
  @State private var showsPrivacy = false
  @State private var managesSubscription = false
  @State private var isRestoring = false
  @State private var restoreLine: String?

  static let deleteFailedLine = "Nothing was deleted. Your sessions are still on this phone."
  static let nothingToRestoreLine = "No subscription found for this Apple Account."

  public static let siteURL = URL(string: "https://ooooh.app")!
  public static let termsURL = URL(string: "https://ooooh.app/terms.html")!

  /// `transcription` names the engine Start runs on this phone; `cloudSync` is what the iCloud row
  /// says; `entitlement` is what the Subscription row says; `subscribeAction` opens the paywall;
  /// `restore` asks the App Store for a past purchase; `openHistory` opens the list where one
  /// session can be deleted; `onDone` adds a Done button when the screen is presented as a sheet.
  public init(
    settings: AppSettings, store: SessionStore, version: String = SettingsView.bundleVersion,
    transcription: String? = nil, cloudSync: CloudSyncState, entitlement: Entitlement,
    subscribeAction: @escaping () -> Void, restore: @escaping () async throws -> Entitlement,
    openHistory: @escaping () -> Void, onDone: (() -> Void)? = nil
  ) {
    self.settings = settings
    self.store = store
    self.version = version
    self.transcription = transcription
    self.cloudSync = cloudSync
    self.entitlement = entitlement
    self.subscribeAction = subscribeAction
    self.restore = restore
    self.openHistory = openHistory
    self.onDone = onDone
  }

  init(
    settings: AppSettings, store: SessionStore, version: String, transcription: String?,
    cloudSync: CloudSyncState, entitlement: Entitlement, now: Date, sessionCount: Int?,
    subscribeAction: @escaping () -> Void, openHistory: @escaping () -> Void,
    onDone: (() -> Void)?
  ) {
    self.init(
      settings: settings, store: store, version: version, transcription: transcription,
      cloudSync: cloudSync, entitlement: entitlement, subscribeAction: subscribeAction,
      restore: { entitlement }, openHistory: openHistory, onDone: onDone)
    _sessionCount = State(initialValue: sessionCount)
    self.now = now
    scrolls = false
  }

  /// "0.1.0 (1)" from the main bundle, or empty outside an app.
  public static var bundleVersion: String {
    let info = Bundle.main.infoDictionary ?? [:]
    guard let short = info["CFBundleShortVersionString"] as? String else { return "" }
    let build = info["CFBundleVersion"] as? String
    return build.map { "\(short) (\($0))" } ?? short
  }

  public var body: some View {
    if scrolls {
      NavigationStack {
        screen(ScrollView { content })
          .navigationDestination(isPresented: $showsPrivacy) { PrivacyView() }
          #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
          #endif
      }
    } else {
      screen(content.fixedSize(horizontal: false, vertical: true))
    }
  }

  private func screen(_ body: some View) -> some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      VStack(spacing: 0) {
        header
        body
      }
    }
    .task { await refreshCount() }
    .onDisappear(perform: ExportFile.removeExports)
    .confirmationDialog(
      deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible
    ) {
      Button("Delete everything", role: .destructive) { deleteEverything() }
    } message: {
      Text(deleteMessage)
    }
    #if os(iOS)
      .manageSubscriptionsSheet(isPresented: $managesSubscription)
    #endif
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("Settings")
        .font(Typography.display)
        .foregroundStyle(Palette.ink)
        .accessibilityAddTraits(.isHeader)
      Spacer()
      if let onDone {
        Button(action: onDone) { Text("Done").tapTarget() }
          .font(.body.weight(.semibold))
          .foregroundStyle(Palette.accent)
          .accessibilityIdentifier("settings.done")
      }
    }
    .padding(.horizontal, 24)
    .padding(.top, 8)
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 28) {
      listener
      subscription
      data
      SettingsSection(title: "Privacy") {
        ActionRow(title: "What leaves your phone, and what stays") { showsPrivacy = true }
      }
      about
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 24)
    .padding(.top, 16)
    .padding(.bottom, 48)
  }

  private var listener: some View {
    SettingsSection(
      title: "Listener",
      footer: "Automatic quiet mode follows the audio route: voice on headphones, a tap on the "
        + "speaker."
    ) {
      Toggle(isOn: $settings.challengeEnabled) {
        RowLabel(title: "Challenge prompts", detail: "Lets the listener push back on an idea")
      }
      .toggleStyle(SkyToggleStyle())
      RowDivider()
      ChoiceRow(
        title: "Quiet mode",
        choices: AppSettings.QuietModeOverride.allCases.map { ($0, $0.title) },
        selection: $settings.quietModeOverride)
      RowDivider()
      RowLabel(title: "Transcription", detail: transcription)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.transcription")
    }
  }

  private var subscription: some View {
    SettingsSection(title: "Subscription", footer: entitlement.settingsFooter) {
      if entitlement.isPaid {
        ActionRow(title: entitlement.settingsLine(now: now)) { managesSubscription = true }
          .accessibilityHint("Opens the App Store's subscription settings")
          .accessibilityIdentifier("settings.subscription")
      } else {
        ActionRow(title: entitlement.settingsLine(now: now), action: subscribeAction)
          .accessibilityIdentifier("settings.subscribe")
      }
      if case .free = entitlement {
        RowDivider()
        ActionRow(title: "Restore Purchases", symbol: "arrow.clockwise") { restorePurchases() }
          .disabled(isRestoring)
          .accessibilityIdentifier("settings.restore")
        if let restoreLine {
          Text(restoreLine)
            .font(Typography.caption)
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
            .accessibilityIdentifier("settings.restoreLine")
        }
      }
    }
  }

  private var data: some View {
    SettingsSection(
      title: "Your data", footer: "The export is a zip with one Markdown file per session."
    ) {
      Toggle(isOn: $settings.cloudSyncEnabled) {
        RowLabel(title: "iCloud sync", detail: cloudSync.line)
      }
      .toggleStyle(SkyToggleStyle())
      .accessibilityIdentifier("settings.cloudSync")
      RowDivider()
      ShareLink(
        item: ExportFile(store: store),
        preview: SharePreview("ooooh export", image: Image(systemName: "doc.zipper"))
      ) {
        HStack(spacing: 12) {
          RowLabel(title: "Export notes")
          Image(systemName: "square.and.arrow.up")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.inkDim)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Export notes as a zip of Markdown")
      .accessibilityIdentifier("settings.export")
      RowDivider()
      ActionRow(title: "Delete one session", detail: "In History", action: openHistory)
        .accessibilityIdentifier("settings.history")
      RowDivider()
      ActionRow(
        title: "Delete everything", detail: countLine, symbol: "trash", color: Palette.accent
      ) {
        confirmingDelete = true
      }
      .disabled(sessionCount == 0)
      .accessibilityIdentifier("settings.deleteAll")
      if let deleteFailure {
        Text(deleteFailure)
          .font(Typography.caption)
          .foregroundStyle(Palette.accent)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.bottom, 12)
          .accessibilityIdentifier("settings.deleteFailure")
      }
    }
  }

  private var about: some View {
    SettingsSection(title: "About") {
      HStack {
        RowLabel(title: "Version")
        Text(version)
          .font(Typography.body)
          .foregroundStyle(Palette.inkDim)
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("settings.version")
      RowDivider()
      Link(destination: Self.siteURL) { linkLabel("ooooh.app") }
      RowDivider()
      Link(destination: PrivacyView.policyURL) { linkLabel("Privacy policy") }
      RowDivider()
      Link(destination: Self.termsURL) { linkLabel("Terms") }
    }
  }

  private func linkLabel(_ title: String) -> some View {
    HStack(spacing: 12) {
      RowLabel(title: title)
      Image(systemName: "arrow.up.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Palette.inkDim)
    }
    .contentShape(Rectangle())
  }

  private var countLine: String? {
    switch sessionCount {
    case nil: nil
    case 0: "Nothing on this phone yet"
    case 1: "1 session on this phone"
    case let count?: "\(count) sessions on this phone"
    }
  }

  private var deleteMessage: String {
    let from = cloudSync == .syncing ? "from this phone and from iCloud" : "from this phone"
    return "Removes every session, with its notes and transcript, \(from). There is no undo."
  }

  private var deleteTitle: String {
    switch sessionCount {
    case 1: "Delete 1 session?"
    case let count?: "Delete \(count) sessions?"
    case nil: "Delete everything?"
    }
  }

  private func refreshCount() async {
    sessionCount = (try? await store.sessionCount()) ?? sessionCount
  }

  /// A paid answer changes `entitlement` through the caller, which replaces the free rows.
  private func restorePurchases() {
    Task {
      isRestoring = true
      defer { isRestoring = false }
      do {
        restoreLine = try await restore().isPaid ? nil : Self.nothingToRestoreLine
      } catch {
        restoreLine = error.localizedDescription
      }
    }
  }

  /// On a store error the count is read again, so the row shows what is still there.
  private func deleteEverything() {
    Task {
      do {
        try await store.deleteEverything()
        ExportFile.removeExports()
        sessionCount = 0
        deleteFailure = nil
      } catch {
        deleteFailure = Self.deleteFailedLine
        await refreshCount()
      }
    }
  }
}
