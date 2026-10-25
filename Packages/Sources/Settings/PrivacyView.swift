import Design
import SwiftUI

/// The privacy policy in short, in the app. The full one is at ooooh.app/privacy.html.
public struct PrivacyView: View {
  /// ImageRenderer draws a ScrollView empty, so snapshots render the content unscrolled.
  var scrolls = true

  public init() {}

  public static let policyURL = URL(string: "https://ooooh.app/privacy.html")!
  public static let contactURL = URL(string: "mailto:hello@ooooh.app")!

  static let intro =
    "ooooh is made by me, Sean Reid. This is what the app does with your words, in short."

  static let sections: [(title: String, paragraphs: [String])] = [
    (
      "What leaves your phone",
      [
        "Your speech is turned into text on the phone. The audio never leaves it.",
        "The transcript and a short structured summary of the session go, as text, through a "
          + "server I run on Cloudflare Workers to three providers. TypeSafe AI runs Jev, which "
          + "decides whether the app should speak. Anthropic runs Claude, which keeps the summary, "
          + "phrases each question, and writes the notes at the end. ElevenLabs turns each "
          + "question into speech.",
        "My server stores none of it. It passes the request through, adds one to a counter, and "
          + "forgets it. Each provider handles the text under its own terms.",
      ]
    ),
    (
      "What my server keeps",
      [
        "There are no accounts, so no name, email address, or password. The server keeps "
          + "counters: requests served, minutes, prompts, and provider failures. It also keeps a "
          + "monthly count of free sessions per device and a count of each device's requests in "
          + "the last minute, which expires within minutes. The device is a random id Apple "
          + "issues to your copy of the app. I can't turn it back into you."
      ]
    ),
    (
      "What stays on your phone",
      [
        "Notes, transcripts, and settings are stored on the device. Audio is discarded when a "
          + "session ends. If you keep the audio for a session, it stays in the app's storage on "
          + "your phone and nowhere else."
      ]
    ),
    (
      "iCloud",
      [
        "With iCloud on, notes, transcripts, and settings sync through your own iCloud account. "
          + "That data sits under your Apple account and Apple's terms. I have no access to it."
      ]
    ),
    (
      "Your controls",
      [
        "From Settings you can delete one session, delete everything, or export everything as "
          + "Markdown. Deleting removes the data from your phone and your iCloud. My server has "
          + "nothing to delete except counters that aren't linked to a person."
      ]
    ),
    (
      "Analytics",
      [
        "There is no analytics SDK in the app. Crash reports reach me only through Apple, under "
          + "the analytics settings on your iPhone."
      ]
    ),
  ]

  public var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      if scrolls {
        ScrollView { content }
      } else {
        content.fixedSize(horizontal: false, vertical: true)
      }
    }
    #if os(iOS)
      .toolbar(.visible, for: .navigationBar)
    #endif
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 28) {
      Text("Privacy")
        .font(Typography.display)
        .foregroundStyle(Palette.ink)
        .accessibilityAddTraits(.isHeader)
      Text(Self.intro)
        .font(Typography.body)
        .foregroundStyle(Palette.ink)
      ForEach(Self.sections, id: \.title) { section in
        VStack(alignment: .leading, spacing: 12) {
          Text(section.title)
            .font(Typography.title)
            .foregroundStyle(Palette.ink)
            .accessibilityAddTraits(.isHeader)
          ForEach(section.paragraphs, id: \.self) { paragraph in
            Text(paragraph)
              .font(Typography.body)
              .foregroundStyle(Palette.ink)
          }
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        Link(destination: Self.policyURL) { Text(verbatim: "Read the full policy at ooooh.app") }
          .frame(minHeight: 44)
        Link(destination: Self.contactURL) { Text(verbatim: "Write to hello@ooooh.app") }
          .frame(minHeight: 44)
      }
      .font(Typography.body)
      .foregroundStyle(Palette.amber)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 24)
    .padding(.top, 8)
    .padding(.bottom, 48)
  }
}
