import Foundation

/// Files the suites read back: what the Worker wrote to a target's Fixtures folder, or what an
/// app test bundle copied in flat.
extension Bundle {
  public struct MissingFixture: Error, CustomStringConvertible {
    public let name: String
    public var description: String { "no fixture named \(name) in the bundle" }
  }

  public func fixtureURL(_ name: String) throws -> URL {
    guard
      let url = url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
        ?? url(forResource: name, withExtension: nil)
    else { throw MissingFixture(name: name) }
    return url
  }

  public func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: fixtureURL(name))
  }

  public func fixture<Value: Decodable>(_ name: String, as type: Value.Type) throws -> Value {
    try JSONDecoder().decode(type, from: fixture(name))
  }
}
