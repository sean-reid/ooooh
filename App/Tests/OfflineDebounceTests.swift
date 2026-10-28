import Foundation
import TestSupport
import Testing

@testable import ooooh

@MainActor
@Suite struct OfflineDebounceTests {
  @Test func aChangeShowsOnceItHasHeldForTheDelay() async throws {
    let debounce = OfflineDebounce(delay: .milliseconds(150))
    debounce.schedule(true)
    #expect(!debounce.isOffline)
    try await Task.sleep(for: .milliseconds(50))
    #expect(!debounce.isOffline)
    await wait { debounce.isOffline }
    #expect(debounce.isOffline)
  }

  @Test func aChangeBackWithinTheDelayDropsTheOneWaiting() async throws {
    let debounce = OfflineDebounce(delay: .milliseconds(150))
    debounce.schedule(true)
    try await Task.sleep(for: .milliseconds(50))
    debounce.schedule(false)
    try await Task.sleep(for: .milliseconds(300))
    #expect(!debounce.isOffline)
  }

  @Test func cancelDropsTheChangeWaitingAndKeepsWhatIsShown() async throws {
    let debounce = OfflineDebounce(delay: .milliseconds(100))
    debounce.schedule(true)
    await wait { debounce.isOffline }
    debounce.schedule(false)
    debounce.cancel()
    try await Task.sleep(for: .milliseconds(250))
    #expect(debounce.isOffline)
  }

  /// A repeat of the state waiting counts from the repeat.
  @Test func theSameStateTwiceRestartsTheWait() async throws {
    let debounce = OfflineDebounce(delay: .milliseconds(300))
    debounce.schedule(true)
    try await Task.sleep(for: .milliseconds(200))
    debounce.schedule(true)
    try await Task.sleep(for: .milliseconds(200))
    #expect(!debounce.isOffline)
    await wait { debounce.isOffline }
    #expect(debounce.isOffline)
  }
}
