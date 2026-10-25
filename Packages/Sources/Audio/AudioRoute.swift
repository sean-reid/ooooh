import Foundation

/// Where sound would come out. Decides quiet mode: speaker means text, anything else means voice.
public enum AudioRoute: Equatable, Sendable {
  case speaker, headphones, car, other

  public var prefersQuietMode: Bool { self == .speaker }
}

/// The one rule for voice versus text: a prompt is spoken unless the route prefers quiet mode.
public func shouldSpeak(route: AudioRoute) -> Bool {
  !route.prefersQuietMode
}
