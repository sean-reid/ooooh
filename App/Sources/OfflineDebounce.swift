import Foundation
import Observation

/// Shows an offline change only once it has held for the delay, so a blip in the Worker's reach
/// neither flickers the orb nor hides a real outage.
@MainActor @Observable
final class OfflineDebounce {
  private(set) var isOffline = false
  private var change: Task<Void, Never>?
  private let delay: Duration

  init(delay: Duration) {
    self.delay = delay
  }

  /// A change back to the state shown drops the one waiting.
  func schedule(_ offline: Bool) {
    change?.cancel()
    guard offline != isOffline else { return }
    change = Task {
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      isOffline = offline
    }
  }

  /// Drops a change still waiting; what is shown stays.
  func cancel() {
    change?.cancel()
  }
}
