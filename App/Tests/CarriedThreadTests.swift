import Foundation
import Governor
import Notes
import Persistence
import Session
import State
import Synchronization
import Testing
import Transcription

@testable import ooooh

/// The real wrapper around a scripted compactor, driven through the fixture loop. Compacting
/// every 30 s puts the short fixture's compactions at 30.0, 60.2, and the end at 87.8, so the
/// second one can remove or resolve the thread and the third shows whether it comes back.
@Suite struct CarriedThreadTests {
  let policy = CompactionPolicy(everySeconds: 30, everyWords: 600)
  let secondCompaction: TimeInterval = 60.2

  final class Marker {}

  /// One patch per compaction from `script`, keeping the state each one was handed.
  final class ScriptedCompactor: Compactor, Sendable {
    let states = Mutex<[CompactState]>([])
    let script: @Sendable (Int) -> StatePatch

    init(_ script: @escaping @Sendable (Int) -> StatePatch) { self.script = script }

    func compact(state: CompactState, transcript: [Segment]) async throws -> StatePatch {
      let index = states.withLock { states in
        states.append(state)
        return states.count - 1
      }
      return script(index)
    }
  }

  /// Every Jev input by session time, and every state a phrasing was given.
  final class Inputs: Sendable {
    let checks = Mutex<[(at: TimeInterval, state: CompactState)]>([])
    let phrasings = Mutex<[CompactState]>([])
  }

  struct RecordingPhraser: Phraser {
    let inputs: Inputs

    func phrase(_ kind: InterventionKind, state: CompactState, recent: [Segment]) async throws
      -> String
    {
      inputs.phrasings.withLock { $0.append(state) }
      return ""
    }
  }

  func fixture() throws -> FixtureTranscriber.Fixture {
    let url = try #require(
      Bundle(for: Marker.self).url(forResource: "short", withExtension: "json"))
    return try JSONDecoder().decode(FixtureTranscriber.Fixture.self, from: Data(contentsOf: url))
  }

  /// A thread the way the carryover card offers one: saved with an earlier session's notes.
  func carriedThread() async throws -> CarriedThread {
    let store = try SessionStore(configuration: .inMemory)
    let earlier = await FixtureDriver.run(
      fixture: try fixture(), config: .initial,
      dependencies: .init(
        decisions: SilentDecisionProvider(), compactor: PassthroughCompactor(),
        phraser: TemplatePhraser()))
    let notes = SessionNotes(
      title: "Pricing and the free tier",
      openThreads: [NoteItem(id: "free-tier-purpose", text: "What the free tier is for")])
    try await store.save(result: earlier, notes: notes, title: notes.title)
    return CarriedThread(try #require(try await store.openThreads(limit: 1).first))
  }

  /// Runs the short fixture with the thread carried, a good moment on the utterance ending at
  /// 70.4 so one phrasing happens after the second compaction.
  func run(_ thread: CarriedThread, compactor: ScriptedCompactor, inputs: Inputs) async throws
    -> SessionResult
  {
    let decisions = ScriptedDecisionProvider { input in
      inputs.checks.withLock { $0.append((input.signals.now, input.state)) }
      var answers = JevAnswers.quiet
      if input.recentTranscript.last?.end == 70.4 {
        answers.goodMoment = .init(0.95)
        answers.intervention = .init(.clarify, confidence: 0.9)
      }
      return answers
    }
    let dependencies = thread.wrap(
      .init(decisions: decisions, compactor: compactor, phraser: RecordingPhraser(inputs: inputs)))
    return await FixtureDriver.run(
      fixture: try fixture(), config: .initial, policy: policy, dependencies: dependencies)
  }

  func patches(_ result: SessionResult) -> [StatePatch] {
    result.records.compactMap {
      if case .compaction(_, let patch) = $0 { patch } else { nil }
    }
  }

  @Test func aThreadTheCompactorRemovesStaysOut() async throws {
    let thread = try await carriedThread()
    let compactor = ScriptedCompactor { index in
      index == 1 ? StatePatch(remove: [thread.id]) : StatePatch()
    }
    let inputs = Inputs()
    let result = try await run(thread, compactor: compactor, inputs: inputs)

    let patches = patches(result)
    #expect(patches.count == 3)
    #expect(patches.map { $0.add.map(\.id) } == [[thread.id], [], []])
    #expect(result.state.openQuestions.isEmpty)
    #expect(
      compactor.states.withLock { $0 }.map { $0.openQuestions.map(\.id) } == [
        [thread.id], [thread.id], [],
      ])

    let checks = inputs.checks.withLock { $0 }
    let before = checks.filter { $0.at < secondCompaction }
    let after = checks.filter { $0.at >= secondCompaction }
    #expect(!before.isEmpty)
    #expect(before.allSatisfy { $0.state.openQuestions.map(\.id) == [thread.id] })
    #expect(!after.isEmpty)
    #expect(after.allSatisfy { $0.state.openQuestions.isEmpty })
    #expect(inputs.phrasings.withLock { $0 }.map(\.openQuestions) == [[]])
  }

  @Test func aThreadTheCompactorLeavesAloneStaysSeeded() async throws {
    let thread = try await carriedThread()
    let compactor = ScriptedCompactor { _ in StatePatch() }
    let inputs = Inputs()
    let result = try await run(thread, compactor: compactor, inputs: inputs)

    let patches = patches(result)
    #expect(patches.map { $0.add.map(\.id) } == [[thread.id], [], []])
    #expect(result.state.openQuestions.map(\.id) == [thread.id])
    #expect(result.state.currentThread == thread.text)
    let compacted = compactor.states.withLock { $0 }
    #expect(
      compacted.map { $0.openQuestions.map(\.id) } == [[thread.id], [thread.id], [thread.id]])

    let checks = inputs.checks.withLock { $0 }
    #expect(checks.count > 3)
    #expect(checks.allSatisfy { $0.state.openQuestions.map(\.id) == [thread.id] })
    #expect(inputs.phrasings.withLock { $0 }.map { $0.openQuestions.map(\.id) } == [[thread.id]])
  }

  @Test func aThreadTheCompactorResolvesIsNotReseeded() async throws {
    let thread = try await carriedThread()
    let compactor = ScriptedCompactor { index in
      index == 1 ? StatePatch(resolve: [thread.id]) : StatePatch()
    }
    let inputs = Inputs()
    let result = try await run(thread, compactor: compactor, inputs: inputs)

    let settled = CompactState.Item(id: thread.id, text: thread.text, resolved: true)
    let patches = patches(result)
    #expect(patches.map { $0.add.map(\.id) } == [[thread.id], [], []])
    #expect(result.state.openQuestions == [settled])
    #expect(compactor.states.withLock { $0 }.last?.openQuestions == [settled])

    let after = inputs.checks.withLock { $0 }.filter { $0.at >= secondCompaction }
    #expect(!after.isEmpty)
    #expect(after.allSatisfy { $0.state.openQuestions == [settled] })
    #expect(inputs.phrasings.withLock { $0 }.map(\.openQuestions) == [[settled]])
  }
}
