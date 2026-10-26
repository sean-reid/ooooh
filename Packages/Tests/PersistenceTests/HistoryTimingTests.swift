import Foundation
import Notes
import SwiftData
import Testing

@testable import Persistence

@Suite struct HistoryTimingTests {
  static let words = """
    pricing tier backend cost session prompt listen notes decide question thread idea cheap money
    minutes hooked free cap expensive comparables shipping launch friend calendar morning plan
    budget design orb palette transcript phone iCloud sync export markdown reminder habit
    """.split(whereSeparator: \.isWhitespace).map(String.init)

  static func line(_ rng: inout SplitMix, words: Int) -> String {
    (0..<words).map { _ in Self.words[Int(rng.next() % UInt64(Self.words.count))] }
      .joined(separator: " ")
  }

  /// 300 sessions, 40 lines each, with two open threads apiece.
  static func seed(_ store: SessionStore) async throws {
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
  }

  @Test func searchOverThreeHundredSessionsStaysUnderBudget() async throws {
    let store = try Support.store()
    try await Self.seed(store)
    #expect(
      try await store.counts() == .init(sessions: 300, segments: 12_000, items: 3_600, threads: 600)
    )

    let clock = ContinuousClock()
    var timings: [String: [Duration]] = [:]
    for _ in 0..<5 {
      for needle in ["zebrawood", "quokka", "calendar"] {
        var found: [SessionSummary] = []
        let elapsed = try await clock.measure { found = try await store.search(needle) }
        timings[needle, default: []].append(elapsed)
        if needle == "zebrawood" { #expect(found.map(\.title) == ["Session 150"]) }
        if needle == "quokka" { #expect(found.map(\.title) == ["Session 200"]) }
        if needle == "calendar" { #expect(found.count == 50) }
      }
    }
    for (needle, runs) in timings.sorted(by: { $0.key < $1.key }) {
      let sorted = runs.sorted()
      let median = sorted[sorted.count / 2]
      print("search \(needle): median \(median), runs \(sorted)")
      #expect(median < .milliseconds(100), "search for \(needle)")
    }
  }

  /// A fresh actor per run, so every session is a fault, as at launch.
  @Test func openThreadsOverThreeHundredSessionsStaysUnderBudget() async throws {
    let store = try Support.store()
    try await Self.seed(store)
    let container = await store.container
    let clock = ContinuousClock()
    var runs: [Duration] = []
    for _ in 0..<5 {
      let cold = SessionStore(modelContainer: container)
      var threads: [OpenThread] = []
      runs.append(try await clock.measure { threads = try await cold.openThreads(limit: 3) })
      #expect(threads.map(\.sessionTitle) == ["Session 299", "Session 299", "Session 298"])
      #expect(threads.map(\.noteItemID) == ["t0", "t1", "t0"])
    }
    let sorted = runs.sorted()
    print("openThreads: median \(sorted[2]), runs \(sorted)")
    #expect(sorted[2] < .milliseconds(20))
  }
}

extension SessionStore {
  var container: ModelContainer { modelContainer }
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
