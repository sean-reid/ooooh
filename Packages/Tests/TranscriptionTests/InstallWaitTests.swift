import Foundation
import Testing

@testable import Transcription

struct InstallWaitTests {
  struct Boom: Error {}

  @Test func returnsWhenTheInstallCallReturns() async throws {
    let outcome = try await InstallWait.run(
      install: { try await Task.sleep(for: .milliseconds(20)) },
      installed: { false },
      every: .milliseconds(5))
    #expect(outcome == .returned)
  }

  @Test func leavesWhenTheInventoryShowsInstalledWhileTheCallHangs() async throws {
    let installed = Flag()
    Task {
      try await Task.sleep(for: .milliseconds(30))
      await installed.set()
    }
    let started = ContinuousClock.now
    let outcome = try await InstallWait.run(
      install: { try await Task.sleep(for: .seconds(60)) },
      installed: { await installed.value },
      every: .milliseconds(5))
    #expect(outcome == .observedInstalled)
    #expect(ContinuousClock.now - started < .seconds(5))
  }

  @Test func throwsWhenTheInstallCallFailsFirst() async {
    await #expect(throws: Boom.self) {
      try await InstallWait.run(
        install: { throw Boom() },
        installed: { false },
        every: .milliseconds(5))
    }
  }

  actor Flag {
    var value = false
    func set() { value = true }
  }
}
