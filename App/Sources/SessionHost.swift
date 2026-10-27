import Foundation
import Observation

/// Owns the controller the screen shows, so an App Intent or a media button reaches the same
/// session the big button does.
@MainActor @Observable
final class SessionHost {
  static let shared = SessionHost(environment: { .app })

  private(set) var controller: SessionController
  /// Builds the environment of every controller, swapped by the tests.
  var environment: @MainActor () -> SessionController.Environment
  /// A start from outside waits for onboarding, which is where permissions are explained.
  var onboarded: @MainActor () -> Bool = {
    UserDefaults.standard.bool(forKey: "onboardingComplete")
  }

  init(environment: @escaping @MainActor () -> SessionController.Environment) {
    self.environment = environment
    controller = SessionController(environment: environment())
  }

  /// A new controller for the next session.
  func reset() {
    controller = SessionController(environment: environment())
  }

  /// What the big button does, from a Siri phrase or the Action button. A running session is
  /// left alone; an ended one gives way to a new one.
  func start() {
    guard onboarded() else { return }
    if controller.stage == .ended { reset() }
    Task { await controller.start(.microphone) }
  }

  func end() async {
    await controller.end()
  }
}
