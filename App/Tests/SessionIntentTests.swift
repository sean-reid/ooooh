import AppIntents
import Foundation
import TestSupport
import Testing

@testable import ooooh

/// The intents reach the shared host, so these tests lend it a microphone that needs no
/// permissions and hand it back when they are done.
@MainActor
@Suite(.serialized) struct SessionIntentTests {
  func lend<T>(_ body: (SessionHost) async throws -> T) async rethrows -> T {
    let host = SessionHost.shared
    let environment = host.environment
    let onboarded = host.onboarded
    host.environment = { downloadEnvironment(HandFedMicrophone()) }
    host.onboarded = { true }
    host.reset()
    defer {
      host.environment = environment
      host.onboarded = onboarded
      host.reset()
    }
    return try await body(host)
  }

  @Test func theStartIntentStartsListeningAndTheEndIntentEndsIt() async throws {
    try await lend { host in
      let controller = host.controller
      #expect(controller.stage == .idle)

      _ = try await StartSessionIntent().perform()
      await wait { controller.stage == .running }
      #expect(controller.phase == .listening)
      #expect(host.controller === controller)

      _ = try await EndSessionIntent().perform()
      #expect(controller.stage == .ended)
      #expect(host.controller === controller)
    }
  }

  @Test func startingAgainLeavesTheRunningSessionAlone() async throws {
    try await lend { host in
      let controller = host.controller
      _ = try await StartSessionIntent().perform()
      await wait { controller.stage == .running }
      let startedAt = controller.startedAt

      _ = try await StartSessionIntent().perform()
      try await Task.sleep(for: .milliseconds(100))
      #expect(host.controller === controller)
      #expect(controller.stage == .running)
      #expect(controller.startedAt == startedAt)
      await host.end()
    }
  }

  @Test func startingAfterAnEndedSessionOpensANewOne() async throws {
    try await lend { host in
      let first = host.controller
      _ = try await StartSessionIntent().perform()
      await wait { first.stage == .running }
      _ = try await EndSessionIntent().perform()
      #expect(first.stage == .ended)

      _ = try await StartSessionIntent().perform()
      #expect(host.controller !== first)
      let second = host.controller
      await wait { second.stage == .running }
      #expect(first.stage == .ended)
      await host.end()
    }
  }

  @Test func endingWithNothingRunningDoesNothing() async throws {
    try await lend { host in
      _ = try await EndSessionIntent().perform()
      #expect(host.controller.stage == .idle)
    }
  }

  @Test func aStartBeforeOnboardingOnlyOpensTheApp() async {
    let host = SessionHost(environment: { downloadEnvironment(HandFedMicrophone()) })
    host.onboarded = { false }
    host.start()
    try? await Task.sleep(for: .milliseconds(100))
    #expect(host.controller.stage == .idle)
  }

  @Test func theProviderOffersAStartAndAnEnd() {
    let shortcuts = OooohShortcuts.appShortcuts
    #expect(shortcuts.count == 2)
  }
}
