import CryptoKit
import Foundation

/// The `appAccountToken` a purchase carries so the Worker can tie the transaction to one install.
public enum AppAccountToken {
  static let prefix = "ooooh.appAccountToken:"
  static let storedKey = "appAccountToken"

  /// The first 16 bytes of SHA-256(prefix + keyId) as a version 8 UUID. The Worker derives the
  /// same value in `appAccountTokenFor` from the attested key id.
  public static func derive(keyId: String) -> UUID {
    var bytes = Array(SHA256.hash(data: Data((prefix + keyId).utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x80
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
  }

  /// Derived from the key id when the install attests, else one random UUID kept in defaults so
  /// the simulator presents the same token every time.
  public static func forInstall(keyId: String?, defaults: UserDefaults = .standard) -> UUID {
    if let keyId { return derive(keyId: keyId) }
    if let stored = defaults.string(forKey: storedKey), let token = UUID(uuidString: stored) {
      return token
    }
    let token = UUID()
    defaults.set(token.uuidString, forKey: storedKey)
    return token
  }
}
