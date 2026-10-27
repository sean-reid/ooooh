import Persistence
import Testing

@testable import Settings

@Suite struct CloudSyncStateTests {
  @Test func theStoreInUseDecidesSyncingAndTheInputsDecideWhyNot() {
    #expect(
      CloudSyncState(configuration: .cloud, accountAvailable: true, syncEnabled: true) == .syncing)
    #expect(
      CloudSyncState(configuration: .local, accountAvailable: true, syncEnabled: false) == .off)
    #expect(
      CloudSyncState(configuration: .local, accountAvailable: false, syncEnabled: true)
        == .noAccount)
    #expect(
      CloudSyncState(configuration: .local, accountAvailable: true, syncEnabled: true) == .failed)
    #expect(CloudSyncState(configuration: nil, accountAvailable: false, syncEnabled: false) == .off)
    #expect(
      CloudSyncState(configuration: nil, accountAvailable: false, syncEnabled: true) == .noAccount)
  }

  @Test func eachStateHasItsOwnLine() {
    let states: [CloudSyncState] = [.syncing, .off, .noAccount, .failed]
    #expect(Set(states.map(\.line)).count == states.count)
    #expect(CloudSyncState.syncing.line == "Syncing with iCloud")
    #expect(CloudSyncState.noAccount.line == "Not signed in to iCloud")
    #expect(CloudSyncState.off.line.hasPrefix("Off"))
  }
}
