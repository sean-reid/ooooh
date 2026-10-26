#if DEBUG
  import Foundation

  /// `-demo-speed 16` plays the demo fixture at sixteen times its recorded pace, so a UI test
  /// reaches the end of a session without waiting out the recording. Unset, zero, negative, or
  /// unreadable is the recorded pace.
  enum DemoSpeed {
    static func read(_ defaults: UserDefaults = .standard) -> Double {
      guard let text = defaults.string(forKey: "demo-speed"), let speed = Double(text), speed > 0
      else { return 1 }
      return speed
    }
  }
#endif
