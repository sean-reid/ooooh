#if os(iOS) && canImport(StoreKitTest)
  import Foundation
  import StoreKitTest

  enum TestSession {
    private final class Token {}

    /// A clean US storefront in English, so prices render as dollars.
    @MainActor
    static func make() throws -> SKTestSession {
      guard
        let url = Bundle(for: Token.self).url(forResource: "Products", withExtension: "storekit")
      else { throw CocoaError(.fileNoSuchFile) }
      let session = try SKTestSession(contentsOf: url)
      session.disableDialogs = true
      session.locale = Locale(identifier: "en_US")
      session.storefront = "USA"
      session.clearTransactions()
      return session
    }
  }
#endif
