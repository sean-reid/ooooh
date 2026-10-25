import Foundation
import Observation

/// The listener settings, read and written straight through UserDefaults under `settings.` keys.
@MainActor @Observable
public final class AppSettings {
  public enum QuietModeOverride: String, CaseIterable, Sendable {
    case auto, voice, quiet

    public var title: String {
      switch self {
      case .auto: "Automatic"
      case .voice: "Always voice"
      case .quiet: "Always quiet"
      }
    }
  }

  enum Key {
    static let challengeEnabled = "settings.challengeEnabled"
    static let keepAudioByDefault = "settings.keepAudioByDefault"
    static let quietModeOverride = "settings.quietModeOverride"
  }

  @ObservationIgnored private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Lets the listener push back on an idea instead of only asking about it. On by default.
  public var challengeEnabled: Bool {
    get {
      access(keyPath: \.challengeEnabled)
      return defaults.object(forKey: Key.challengeEnabled) as? Bool ?? true
    }
    set {
      withMutation(keyPath: \.challengeEnabled) {
        defaults.set(newValue, forKey: Key.challengeEnabled)
      }
    }
  }

  /// The default for a new session's keep-audio switch. Off by default.
  public var keepAudioByDefault: Bool {
    get {
      access(keyPath: \.keepAudioByDefault)
      return defaults.bool(forKey: Key.keepAudioByDefault)
    }
    set {
      withMutation(keyPath: \.keepAudioByDefault) {
        defaults.set(newValue, forKey: Key.keepAudioByDefault)
      }
    }
  }

  /// Automatic follows the audio route: voice on headphones, a tap on the speaker.
  public var quietModeOverride: QuietModeOverride {
    get {
      access(keyPath: \.quietModeOverride)
      let raw = defaults.string(forKey: Key.quietModeOverride) ?? ""
      return QuietModeOverride(rawValue: raw) ?? .auto
    }
    set {
      withMutation(keyPath: \.quietModeOverride) {
        defaults.set(newValue.rawValue, forKey: Key.quietModeOverride)
      }
    }
  }
}
