import XCTest

/// Where the app under test finds the Worker. `TEST_RUNNER_OOOOH_WORKER_URL` on the xcodebuild
/// command line picks another port.
enum Worker {
  static let url =
    ProcessInfo.processInfo.environment["OOOOH_WORKER_URL"] ?? "http://localhost:8787"
  static let launchArguments = ["-worker-url", url]
}

extension XCTestCase {
  /// Skips the test when nothing answers at the Worker URL.
  @MainActor
  func requireWorker() async throws {
    let url = try XCTUnwrap(URL(string: Worker.url)).appending(path: "v1/config")
    var request = URLRequest(url: url)
    request.timeoutInterval = 3
    let reachable = (try? await URLSession.shared.data(for: request)) != nil
    try XCTSkipUnless(reachable, "no Worker at \(Worker.url)")
  }
}
