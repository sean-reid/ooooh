import Foundation
import Security

/// Where the attested key id lives between launches.
protocol KeyIdStore: Sendable {
  /// Nil when nothing is stored. Throws when the store cannot answer, which is not the same thing.
  func read() throws -> String?
  func write(_ keyId: String) throws
  func delete()
}

/// One keychain item for the app.
struct KeychainKeyIdStore: KeyIdStore {
  var query: [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: "com.seanreid.ooooh.appattest",
      kSecAttrAccount: "keyId",
    ]
  }

  func read() throws -> String? {
    var item: CFTypeRef?
    let status = SecItemCopyMatching(
      query.merging([kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]) { $1 }
        as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data else { return nil }
      return String(data: data, encoding: .utf8)
    case errSecItemNotFound:
      return nil
    default:
      throw ProxyError.attestation("keychain read \(status)")
    }
  }

  func write(_ keyId: String) throws {
    delete()
    let status = SecItemAdd(
      query.merging([
        kSecValueData: Data(keyId.utf8),
        kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      ]) { $1 } as CFDictionary, nil)
    guard status == errSecSuccess else { throw ProxyError.attestation("keychain write \(status)") }
  }

  func delete() {
    SecItemDelete(query as CFDictionary)
  }
}
