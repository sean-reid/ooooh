import Foundation

/// Waits for a system install to finish by either signal: the install call returning, or the
/// inventory reporting the asset installed. The first launch on some phones installs the asset
/// and then never returns from the call, which left the download screen up until a relaunch.
enum InstallWait {
  enum Outcome: Equatable, Sendable {
    case returned
    case observedInstalled
  }

  /// Runs `install` and polls `installed` every `interval`; whichever finishes first wins, and an
  /// error from `install` before the asset shows as installed is thrown.
  static func run(
    install: @escaping @Sendable () async throws -> Void,
    installed: @escaping @Sendable () async -> Bool,
    every interval: Duration = .seconds(1)
  ) async throws -> Outcome {
    try await withThrowingTaskGroup(of: Outcome.self) { group in
      group.addTask {
        try await install()
        return .returned
      }
      group.addTask {
        while true {
          try await Task.sleep(for: interval)
          if await installed() { return .observedInstalled }
        }
      }
      defer { group.cancelAll() }
      guard let first = try await group.next() else { return .returned }
      return first
    }
  }
}
