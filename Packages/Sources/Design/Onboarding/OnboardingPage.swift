/// The first-run screens, in order. The last one holds the Start button.
public enum OnboardingPage: String, CaseIterable, Sendable {
  case listen
  case speaks
  case start

  public var title: String? {
    switch self {
    case .listen: "Think out loud."
    case .speaks: "It waits."
    case .start: nil
    }
  }

  public var text: String {
    switch self {
    case .listen:
      """
      You talk for as long as you need, and your listener keeps track. \
      When you stop, the session becomes notes: ideas, decisions, questions, and open threads.
      """
    case .speaks:
      """
      Your listener stays quiet and follows along. It asks one short question when a thread \
      hangs, a point repeats, or a decision goes unnamed. With the phone on a desk and nothing \
      plugged in, quiet mode shows the question beside the orb instead of speaking it.
      """
    case .start:
      "Start asks for the microphone and speech recognition, then listens."
    }
  }

  public var next: OnboardingPage? {
    let all = Self.allCases
    let index = all.firstIndex(of: self)! + 1
    return index < all.count ? all[index] : nil
  }

  public var previous: OnboardingPage? {
    let all = Self.allCases
    let index = all.firstIndex(of: self)! - 1
    return index >= 0 ? all[index] : nil
  }

  var number: Int { Self.allCases.firstIndex(of: self)! + 1 }
}

/// What Start was refused, each with its own recovery line.
public enum CaptureDenial: String, CaseIterable, Sendable {
  case microphone
  case speechRecognition

  public var title: String {
    switch self {
    case .microphone: "Your listener cannot hear without the microphone."
    case .speechRecognition: "Your listener cannot follow along without speech recognition."
    }
  }

  public var text: String {
    switch self {
    case .microphone: "Allow the microphone for ooooh in Settings, then come back."
    case .speechRecognition: "Allow speech recognition for ooooh in Settings, then come back."
    }
  }
}
