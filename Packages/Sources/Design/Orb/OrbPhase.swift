public enum OrbPhase: String, CaseIterable, Sendable {
  case resting
  case listening
  case aboutToSpeak
  case speaking
  case offline

  public var accessibilityLabel: String {
    switch self {
    case .resting: "Your listener, resting"
    case .listening: "Your listener is listening"
    case .aboutToSpeak: "Your listener is about to speak"
    case .speaking: "Your listener is speaking"
    case .offline: "Your listener is offline"
    }
  }
}
