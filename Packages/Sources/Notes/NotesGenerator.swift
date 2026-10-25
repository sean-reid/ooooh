import State
import Transcription

/// Writes the notes for a finished session from its compact state and full transcript.
public protocol NotesGenerator: Sendable {
  func generate(state: CompactState, transcript: [Segment]) async throws -> SessionNotes
}
