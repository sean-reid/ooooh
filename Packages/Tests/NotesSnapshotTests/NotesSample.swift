import Foundation
import Notes
import Transcription

/// Two sessions as the view will see them: a long one with every section, a short one that
/// collapsed to a paragraph and its open threads.
enum NotesSample {
  static let transcript = [
    Segment(
      text:
        "Two options. The one on Carver Street, which is the cheap one, and the one by the park.",
      start: 12, end: 21, isFinal: true),
    Segment(
      text: "Carver is about a thousand less. Which is a lot. That is real money.",
      start: 22, end: 29, isFinal: true),
    Segment(
      text: "But Carver is also fifty five minutes door to door. Each way. On a good day.",
      start: 33, end: 44, isFinal: true),
    Segment(
      text: "So the trade is money versus time. Here it is literally the trade.",
      start: 44, end: 53, isFinal: true),
    Segment(
      text: "Times five days. Seven and a half hours a week. Seven and a half hours a week.",
      start: 67, end: 73, isFinal: true),
    Segment(
      text: "Okay. Park. I am going to say park and see how that sits overnight.",
      start: 180, end: 188, isFinal: true),
  ]

  /// Two lines the app said, the deepen one marked bad.
  static let lines = [
    SpokenLine(
      id: UUID(uuidString: "5A1D6E2C-0F3B-4C7A-9E8D-1B2C3D4E5F60")!,
      text: "What would those seven and a half hours go to?", kind: .intervention(.deepen),
      at: 75.4, spoken: true, bad: true),
    SpokenLine(
      id: UUID(uuidString: "7C2E8F4A-1B5D-4E9C-8A7B-2C3D4E5F6071")!, text: "Done for now?",
      kind: .finishedQuestion, at: 190.2, spoken: false),
  ]

  static let full = SessionNotes(
    title: "Carver Street versus the apartment by the park",
    ideas: [
      NoteItem(
        id: "money-versus-time", text: "The trade is a thousand a month against time.",
        span: TranscriptSpan(start: 44, end: 53)),
      NoteItem(
        id: "try-the-commute", text: "Do the Carver commute once before signing anything.",
        span: TranscriptSpan(start: 33, end: 44)),
    ],
    decisions: [
      NoteItem(
        id: "say-park", text: "Park, and see how it sits overnight.",
        span: TranscriptSpan(start: 180, end: 188))
    ],
    questions: [
      NoteItem(
        id: "what-the-hours-buy", text: "What would the seven and a half hours a week go to?",
        span: TranscriptSpan(start: 67, end: 73))
    ],
    insights: [
      NoteItem(
        id: "time-is-the-real-cost", text: "The commute is the cost, not the rent.",
        span: TranscriptSpan(start: 44, end: 73))
    ],
    actions: [
      NoteItem(
        id: "answer-by-monday", text: "Answer the landlord by Monday.",
        span: TranscriptSpan(start: 0, end: 11))
    ],
    openThreads: [
      NoteItem(
        id: "ask-about-lease", text: "Ask whether the park lease can run eighteen months.",
        span: nil),
      NoteItem(
        id: "savings-rate", text: "Whether a thousand a month changes the savings plan.",
        span: TranscriptSpan(start: 22, end: 29), resolved: true),
    ],
    quotes: [
      NoteItem(
        id: "real-money", text: "That is real money.", span: TranscriptSpan(start: 22, end: 29)),
      NoteItem(
        id: "literally-the-trade", text: "Here it is literally the trade.",
        span: TranscriptSpan(start: 44, end: 53)),
    ])

  static let short = SessionNotes(
    title: "A quick pass at the apartment question",
    summary:
      "Two minutes on the two apartments. Carver Street is about a thousand a month cheaper and fifty five minutes each way; the one by the park is twelve minutes on foot. The session stopped before anything was settled.",
    openThreads: [
      NoteItem(
        id: "money-or-time", text: "Which matters more this year, the money or the time.",
        span: TranscriptSpan(start: 44, end: 53)),
      NoteItem(
        id: "try-the-commute", text: "Try the Carver commute once before deciding.", span: nil),
    ])

  static let date = Date(timeIntervalSince1970: 1_792_900_000)
}
