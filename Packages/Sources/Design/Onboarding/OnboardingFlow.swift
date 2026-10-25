import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// The first-run screens, swiped or tapped through. `start` asks for the permissions and
/// returns what was refused, if anything; `done` runs once both are granted.
public struct OnboardingFlow: View {
  public var start: @MainActor () async -> CaptureDenial?
  public var done: @MainActor () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var page = OnboardingPage.listen
  @State private var movesForward = true
  @State private var isStarting = false
  @State private var denial: CaptureDenial?

  public init(
    start: @escaping @MainActor () async -> CaptureDenial?,
    done: @escaping @MainActor () -> Void
  ) {
    self.start = start
    self.done = done
  }

  public var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      if let denial {
        PermissionRecoveryScreen(denial: denial, openSettings: Self.openSettings)
          .transition(.opacity)
      } else {
        OnboardingScreen(page: page, isStarting: isStarting, select: select, start: begin)
          .id(page)
          .transition(pageTransition)
          .simultaneousGesture(swipe)
      }
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: page)
    .animation(.easeInOut(duration: 0.3), value: denial)
    .onChange(of: page) { _, page in
      AccessibilityNotification.PageScrolled(
        "Page \(page.number) of \(OnboardingPage.allCases.count)"
      ).post()
    }
  }

  private var pageTransition: AnyTransition {
    if reduceMotion { return .opacity }
    return .push(from: movesForward ? .trailing : .leading)
  }

  private var swipe: some Gesture {
    DragGesture(minimumDistance: 24).onEnded { value in
      let width = value.translation.width
      guard abs(width) > 60, abs(width) > abs(value.translation.height) else { return }
      if width < 0, let next = page.next { select(next) }
      if width > 0, let previous = page.previous { select(previous) }
    }
  }

  private func select(_ target: OnboardingPage) {
    movesForward = target.number > page.number
    page = target
  }

  private func begin() {
    guard !isStarting else { return }
    isStarting = true
    Task {
      let refused = await start()
      isStarting = false
      denial = refused
      if refused == nil { done() }
    }
  }

  /// Opens the app's own page in Settings, where the two permissions live.
  @MainActor static func openSettings() {
    #if canImport(UIKit) && !os(watchOS)
      guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
      UIApplication.shared.open(url)
    #endif
  }
}
