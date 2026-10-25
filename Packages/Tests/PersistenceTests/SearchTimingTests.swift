import Foundation
import Notes
import Testing

@testable import Persistence

@Suite struct SearchTimingTests {
  static let words = """
    pricing tier backend cost session prompt listen notes decide question thread idea cheap money
    minutes hooked free cap expensive comparables shipping launch friend calendar morning plan
    budget design orb palette transcript phone iCloud sync export markdown reminder habit
    """.split(whereSeparator: \.isWhitespace).map(String.init)

  static func line(_ rng: inout SplitMix, words: Int) -> String {
    (0..<words).map { _ in Self.words[Int(rng.next() % UInt64(Self.words.count))] }
      .joined(separator: " ")
  }

  @Test func searchOverThreeHundredSessionsStaysUnderBudget() async throws {
    let store = try Support.store()
    var rng = SplitMix(seed: 7)
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    for index in 0..<300 {
      var lines = (0..<40).map { _ in Self.line(&rng, words: 9) }
      if index == 150 { lines[20] += " zebrawood" }
      var notes = SessionNotes(title: "Session \(index)")
      notes.ideas = (0..<4).map { NoteItem(id: "i\($0)", text: Self.line(&rng, words: 6)) }
      notes.decisions = (0..<3).map { NoteItem(id: "d\($0)", text: Self.line(&rng, words: 6)) }
      notes.actions = (0..<3).map { NoteItem(id: "a\($0)", text: Self.line(&rng, words: 5)) }
      notes.openThreads = (0..<2).map { NoteItem(id: "t\($0)", text: Self.line(&rng, words: 5)) }
      if index == 200 { notes.actions[1].text += " quokka" }
      try await store.save(
        result: await Support.result(lines: lines), notes: notes, title: "",
        startedAt: base.addingTimeInterval(Double(index) * 3600))
    }
    #expect(try await store.counts().segments == 12_000)
    #expect(try await store.counts().items == 3_600)

    let clock = ContinuousClock()
    var timings: [String: [Duration]] = [:]
    for _ in 0..<5 {
      for needle in ["zebrawood", "quokka", "calendar"] {
        var found: [SessionSummary] = []
        let elapsed = try await clock.measure { found = try await store.search(needle) }
        timings[needle, default: []].append(elapsed)
        if needle == "zebrawood" { #expect(found.map(\.title) == ["Session 150"]) }
        if needle == "quokka" { #expect(found.map(\.title) == ["Session 200"]) }
        if needle == "calendar" { #expect(found.count > 100) }
      }
    }
    for (needle, runs) in timings.sorted(by: { $0.key < $1.key }) {
      let sorted = runs.sorted()
      let median = sorted[sorted.count / 2]
      print("search \(needle): median \(median), runs \(sorted)")
      #expect(median < .milliseconds(100), "search for \(needle)")
    }
  }
}

struct SplitMix {
  var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
