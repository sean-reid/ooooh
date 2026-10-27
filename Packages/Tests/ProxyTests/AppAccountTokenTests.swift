import Foundation
import TestSupport
import Testing

@testable import Proxy

@Suite struct AppAccountTokenTests {
  struct Case: Decodable {
    var keyId: String
    var appAccountToken: String
  }

  @Test func derivesTheTokenTheWorkerDerivesForEveryFixtureKeyId() throws {
    let cases = try JSONDecoder().decode(
      [Case].self, from: Bundle.module.fixture("app-account-token.json"))
    #expect(cases.count == 3)
    for item in cases {
      #expect(
        AppAccountToken.derive(keyId: item.keyId).uuidString.lowercased() == item.appAccountToken)
    }
  }

  @Test func isStableForOneKeyIdAndDistinctAcrossKeyIds() {
    let first = AppAccountToken.derive(keyId: "pZlz6oUGm/8DbqJj8ms+QDU6KoMo9n5bPcz3uUkfk1E=")
    #expect(AppAccountToken.derive(keyId: "pZlz6oUGm/8DbqJj8ms+QDU6KoMo9n5bPcz3uUkfk1E=") == first)
    #expect(AppAccountToken.derive(keyId: "pZlz6oUGm/8DbqJj8ms+QDU6KoMo9n5bPcz3uUkfk1F=") != first)
    let text = first.uuidString.lowercased()
    #expect(text[text.index(text.startIndex, offsetBy: 14)] == "8")
    #expect("89ab".contains(text[text.index(text.startIndex, offsetBy: 19)]))
  }

  @Test func anInstallWithoutAKeyIdKeepsOneRandomToken() throws {
    let names = [
      "AppAccountTokenTests.\(UUID().uuidString)", "AppAccountTokenTests.\(UUID().uuidString)",
    ]
    let defaults = try names.map { try #require(UserDefaults(suiteName: $0)) }
    defer { for name in names { UserDefaults.standard.removePersistentDomain(forName: name) } }

    let first = AppAccountToken.forInstall(keyId: nil, defaults: defaults[0])
    #expect(AppAccountToken.forInstall(keyId: nil, defaults: defaults[0]) == first)
    #expect(AppAccountToken.forInstall(keyId: nil, defaults: defaults[1]) != first)
    #expect(
      AppAccountToken.forInstall(keyId: "k", defaults: defaults[0])
        == AppAccountToken.derive(keyId: "k"))
  }
}
