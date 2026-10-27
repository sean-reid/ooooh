import SwiftUI
import Testing
import UIKit

@testable import ooooh

/// The root view in a window: the launch work the first frame does not need runs from its task
/// once it is on screen, not from its init or its body.
@MainActor
@Suite struct LaunchWorkTests {
  @Test func theRootViewRunsTheLaunchWorkAfterTheFirstFrame() async {
    let launch = LaunchWork()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let host = UIHostingController(rootView: RootView(launch: launch))
    #expect(!launch.isDone)

    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    #expect(!launch.isDone)

    let deadline = ContinuousClock.now + .seconds(5)
    while !launch.isDone, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(launch.isDone)
    window.isHidden = true
  }
}
