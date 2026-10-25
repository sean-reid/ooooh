import Foundation
import Testing

@testable import State

@Suite struct StatePatchTests {
  @Test func addsResolvesAndRemoves() throws {
    let patch = StatePatch(
      currentThread: "cost versus motivation",
      add: [
        .init(list: .mainIdeas, id: "i1", text: "cost is the real blocker"),
        .init(list: .openQuestions, id: "q1", text: "what would make it feel worth it"),
      ])
    var state = try CompactState.empty.applying(patch)
    #expect(state.mainIdeas.map(\.text) == ["cost is the real blocker"])
    #expect(state.currentThread == "cost versus motivation")

    state = try state.applying(StatePatch(resolve: ["q1"]))
    #expect(state.openQuestions.first?.resolved == true)

    state = try state.applying(StatePatch(remove: ["i1"]))
    #expect(state.mainIdeas.isEmpty)
  }

  @Test func rejectsDuplicateIDsWithoutMutating() {
    let base = try! CompactState.empty.applying(
      StatePatch(add: [.init(list: .decisions, id: "d1", text: "ship in spring")]))
    let bad = StatePatch(add: [.init(list: .mainIdeas, id: "d1", text: "again")])
    #expect(throws: PatchError.duplicateID("d1")) { try base.applying(bad) }
    #expect(base.mainIdeas.isEmpty)
  }

  @Test func rejectsUnknownAndEmpty() {
    #expect(throws: PatchError.unknownID("nope")) {
      try CompactState.empty.applying(StatePatch(resolve: ["nope"]))
    }
    #expect(throws: PatchError.emptyText("x")) {
      try CompactState.empty.applying(
        StatePatch(add: [.init(list: .mainIdeas, id: "x", text: "   ")]))
    }
  }

  @Test func boundsLists() {
    let adds = (0..<13).map {
      StatePatch.Addition(list: .mainIdeas, id: "i\($0)", text: "idea \($0)")
    }
    #expect(throws: PatchError.listOverflow(.mainIdeas, limit: 12)) {
      try CompactState.empty.applying(StatePatch(add: adds))
    }
  }

  @Test func roundTripsThroughJSON() throws {
    let state = try CompactState.empty.applying(
      StatePatch(
        mode: .stuck, recentTopics: ["a", "b"],
        add: [.init(list: .uncertainties, id: "u1", text: "not sure about timing")]))
    let data = try JSONEncoder().encode(state)
    let back = try JSONDecoder().decode(CompactState.self, from: data)
    #expect(back == state)
  }
}
