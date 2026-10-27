import Foundation

extension Bundle {
  /// This test bundle, which carries the Worker's and the session fixtures as flat resources.
  static let tests: Bundle = {
    final class Marker {}
    return Bundle(for: Marker.self)
  }()
}
