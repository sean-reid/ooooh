import Governor
import Persistence
import Session
import State
import Synchronization
import Transcription

/// A past session's open thread, put into the state every provider sees. The loop starts
/// from an empty state, so the thread rides along until the first compaction writes it in,
/// and stops riding once a compaction removes it or marks it resolved.
final class CarriedThread: Sendable {
  let text: String
  let id: String
  private let open = Mutex<Bool>(true)

  init(_ thread: OpenThread) {
    text = thread.text
    id = "carried-\(thread.noteItemID)"
  }

  func seed(_ state: CompactState) -> CompactState {
    guard needsSeeding(state) else { return state }
    var state = state
    if state.currentThread.isEmpty { state.currentThread = text }
    state.openQuestions.insert(CompactState.Item(id: id, text: text), at: 0)
    return state
  }

  func wrap(_ dependencies: SessionLoop.Dependencies) -> SessionLoop.Dependencies {
    SessionLoop.Dependencies(
      decisions: Decisions(base: dependencies.decisions, thread: self),
      compactor: Compacting(base: dependencies.compactor, thread: self),
      phraser: Phrasing(base: dependencies.phraser, thread: self))
  }

  private func needsSeeding(_ state: CompactState) -> Bool {
    open.withLock { $0 } && !state.openQuestions.contains { $0.id == id }
  }

  /// Reads the thread as it stands once a patch lands; gone or resolved closes it.
  private func settle(after state: CompactState) {
    let item = state.allItems.first { $0.id == id }
    guard item == nil || item?.resolved == true else { return }
    open.withLock { $0 = false }
  }

  private struct Decisions: DecisionProvider {
    let base: any DecisionProvider
    let thread: CarriedThread

    func check(_ input: CheckInput) async throws -> JevAnswers {
      var input = input
      input.state = thread.seed(input.state)
      return try await base.check(input)
    }
  }

  private struct Phrasing: Phraser {
    let base: any Phraser
    let thread: CarriedThread

    func phrase(_ kind: InterventionKind, state: CompactState, recent: [Segment]) async throws
      -> String
    {
      try await base.phrase(kind, state: thread.seed(state), recent: recent)
    }
  }

  /// The patch is applied to the unseeded state, so the thread is added the first time through.
  private struct Compacting: Compactor {
    let base: any Compactor
    let thread: CarriedThread

    func compact(state: CompactState, transcript: [Segment]) async throws -> StatePatch {
      var patch = try await base.compact(state: thread.seed(state), transcript: transcript)
      if thread.needsSeeding(state) {
        patch.add.insert(
          StatePatch.Addition(list: .openQuestions, id: thread.id, text: thread.text), at: 0)
        if patch.currentThread == nil, state.currentThread.isEmpty {
          patch.currentThread = thread.text
        }
      }
      if let next = try? state.applying(patch) { thread.settle(after: next) }
      return patch
    }
  }
}
