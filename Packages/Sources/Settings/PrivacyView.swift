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
        "Your speech is turned into text on the phone. The audio never leaves it. The app keeps "
          + "listening with the screen locked while a session is running.",
        "The transcript and a short structured summary of the session go, as text, through a "
          + "server I run on Cloudflare Workers to three providers. TypeSafe AI runs Jev, which "
          + "decides whether the app should speak. Anthropic runs Claude, which keeps the summary, "
          + "phrases each question, and writes the notes at the end. ElevenLabs turns each "
          + "question into speech.",
        "My server stores none of it. It passes the request through and forgets it. The one "
          + "thing it writes is what the call cost, added to a counter per provider per day that "
          + "names no device and is gone after three days. Each provider handles the text under "
          + "its own terms.",
      ]
    ),
    (
      "What my server keeps",
      [
        "There are no accounts, so no name, email address, or password. The device is the "
          + "identity: Apple's App Attest proves a request comes from a real copy of the app, and "
          + "my server keeps a few records per device, each keyed on the App Attest key id and "
          + "nothing else. The key id is a random value Apple issues to your copy of the app. I "
          + "can't turn it back into you. The records are:",
        "The public key your phone attested, with a counter that moves forward on every signed "
          + "request. No expiry.",
        "The month's count of free sessions and the minutes they ran. 62 days.",
        "The open session, so a second start while one is running counts nothing. Four hours.",
        "The subscription record, with an account token derived from the key id, so it names an "
          + "install and not a person. 30 days past the subscription's expiry.",
        "A count of signed requests in the current minute. Two minutes. The two calls that enrol "
          + "a key happen before there is a key id, so those are counted per IP address instead, "
          + "for the same two minutes.",
        "A one-time challenge for enrolling a key. Five minutes, or until it's used.",
        "None of it holds a name, an email address, an Apple ID, audio, or a transcript. Every "
          + "signed request carries the time it was signed; my server checks that against its "
          + "clock and doesn't store it.",
      ]
    ),
    (
      "What stays on your phone",
      [
        "Audio is discarded when a session ends. Notes, transcripts, and settings are stored on "
          + "the phone.",
        "While the phone is signed in to iCloud, your sessions also live in your private iCloud "
          + "database, so a new phone gets them back. Apple holds that copy under your Apple "
          + "Account; I can't read it, and my server never sees it. While sync is on, signing out "
          + "of iCloud removes the local copy from the phone, as iOS does for every app that "
          + "mirrors its data to iCloud. You can turn sync off in Settings, and the copy already "
          + "in iCloud stays until you delete everything.",
      ]
    ),
    (
      "Your controls",
      [
        "From Settings you can delete one session, delete everything, or export your notes as "
          + "Markdown. Deleting removes the data from your phone, and from iCloud when sync is "
          + "on. The records on my server age out on the schedule above, the attested public key "
          + "excepted, and none of them is linked to you."
      ]
    ),
    (
      "Analytics",
      [
        "There is no analytics SDK in the app. Crash reports and performance data reach me only "
          + "through Apple, and only if sharing with app developers is on in your iPhone's "
          + "analytics settings."
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
        Link(destination: Self.policyURL) {
          Text(verbatim: "Read the full policy at ooooh.app").tapTarget(alignment: .leading)
        }
        Link(destination: Self.contactURL) {
          Text(verbatim: "Write to hello@ooooh.app").tapTarget(alignment: .leading)
        }
      }
      .font(Typography.body)
      .foregroundStyle(Palette.accent)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 24)
    .padding(.top, 8)
    .padding(.bottom, 48)
  }
}
