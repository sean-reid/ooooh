#if canImport(UIKit)
  import SwiftUI
  import Testing
  import UIKit

  @testable import Design

  @Observable @MainActor
  private final class OrbInput {
    var level = 0.0
    var phase = OrbPhase.resting
  }

  private struct HostedOrb: View {
    let input: OrbInput
    let motion: OrbMotion

    var body: some View {
      Orb(level: input.level, phase: input.phase, motion: motion).frame(width: 240, height: 240)
    }
  }

  /// Hosts the live orb in a window and counts the frames its timeline drew.
  @MainActor
  @Suite(.serialized) struct OrbTimelineTests {
    @Test func restingOrbDrawsOnceThenWakesOnLevel() async throws {
      let input = OrbInput()
      let motion = OrbMotion()
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 240, height: 240))
      window.rootViewController = UIHostingController(
        rootView: HostedOrb(input: input, motion: motion))
      window.makeKeyAndVisible()
      defer { window.isHidden = true }
      try await Task.sleep(for: .seconds(1))
      let atRest = motion.frames
      #expect(atRest >= 1 && atRest <= 2, "drew \(atRest) frames at rest")
      input.level = 0.4
      try await Task.sleep(for: .milliseconds(500))
      #expect(motion.frames >= atRest + 5, "drew \(motion.frames - atRest) frames after waking")
    }

    @Test func listeningOrbKeepsDrawing() async throws {
      let input = OrbInput()
      input.phase = .listening
      input.level = 0.3
      let motion = OrbMotion()
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 240, height: 240))
      window.rootViewController = UIHostingController(
        rootView: HostedOrb(input: input, motion: motion))
      window.makeKeyAndVisible()
      defer { window.isHidden = true }
      try await Task.sleep(for: .seconds(1))
      #expect(motion.frames >= 5, "drew \(motion.frames) frames while listening")
    }
  }
#endif
