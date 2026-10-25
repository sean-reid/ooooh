import Foundation

/// Where sound would come out. Decides quiet mode: speaker means text, anything else means voice.
public enum AudioRoute: Equatable, Sendable {
  case speaker, headphones, car, other

  public var prefersQuietMode: Bool { self == .speaker }
}
