import Foundation

/// Where the app under test finds the Worker. `TEST_RUNNER_OOOOH_WORKER_URL` on the xcodebuild
/// command line picks another port.
enum Worker {
  static let url =
    ProcessInfo.processInfo.environment["OOOOH_WORKER_URL"] ?? "http://localhost:8787"
  static let launchArguments = ["-worker-url", url]
}
