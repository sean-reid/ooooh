import Design
import Persistence
import SwiftUI

/// The settings screen: listener switches, subscription, data controls, privacy, about.
public struct SettingsView: View {
  @Bindable var settings: AppSettings
  var store: SessionStore
  var version: String
  var subscribeAction: () -> Void
  var openHistory: () -> Void
  var onDone: (() -> Void)?
  /// ImageRenderer draws a NavigationStack and a ScrollView empty, so snapshots render the
  /// content flat.
  var scrolls = true
  @State private var sessionCount: Int?
  @State private var confirmingDelete = false
  @State private var deleteFailure: String?
  @State private var showsPrivacy = false

  static let deleteFailedLine = "Nothing was deleted. Your sessions are still on this phone."

  public static let siteURL = URL(string: "https://ooooh.app")!
  public static let termsURL = URL(string: "https://ooooh.app/terms.html")!

  /// `subscribeAction` opens the paywall; `openHistory` opens the list where one session can
  /// be deleted; `onDone` adds a Done button when the screen is presented as a sheet.
  public init(
    settings: AppSettings, store: SessionStore, version: String = SettingsView.bundleVersion,
    subscribeAction: @escaping () -> Void, openHistory: @escaping () -> Void,
    onDone: (() -> Void)? = nil
  ) {
    self.settings = settings
    self.store = store
    self.version = version
    self.subscribeAction = subscribeAction
    self.openHistory = openHistory
    self.onDone = onDone
  }

  init(
    settings: AppSettings, store: SessionStore, version: String, sessionCount: Int?,
    subscribeAction: @escaping () -> Void, openHistory: @escaping () -> Void,
    onDone: (() -> Void)?
  ) {
    self.init(
      settings: settings, store: store, version: version, subscribeAction: subscribeAction,
      openHistory: openHistory, onDone: onDone)
    _sessionCount = State(initialValue: sessionCount)
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
      Text(
        "Removes every session, with its notes and transcript, from this phone. There is no undo."
      )
    }
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
      SettingsSection(title: "Subscription") {
        ActionRow(title: "Subscribe", action: subscribeAction)
          .accessibilityIdentifier("settings.subscribe")
      }
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
    }
  }

  private var data: some View {
    SettingsSection(
      title: "Your data", footer: "The export is a zip with one Markdown file per session."
    ) {
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
