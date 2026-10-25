import SwiftUI

/// One first-run screen: the orb, the words, the page dots, and Next or Start.
public struct OnboardingScreen: View {
  public var page: OnboardingPage
  public var orbTime: TimeInterval?
  public var isStarting: Bool
  public var select: @MainActor (OnboardingPage) -> Void
  public var start: @MainActor () -> Void
  /// ImageRenderer draws a ScrollView empty, so snapshots render the content unscrolled.
  var scrolls = true

  @Environment(\.dynamicTypeSize) private var typeSize

  /// A fixed `orbTime` renders one still frame of the orb; nil animates.
  public init(
    page: OnboardingPage, orbTime: TimeInterval? = nil, isStarting: Bool = false,
    select: @escaping @MainActor (OnboardingPage) -> Void,
    start: @escaping @MainActor () -> Void
  ) {
    self.page = page
    self.orbTime = orbTime
    self.isStarting = isStarting
    self.select = select
    self.start = start
  }

  public var body: some View {
    VStack(spacing: 0) {
      if !typeSize.isAccessibilitySize {
        Spacer(minLength: 0)
        content.layoutPriority(1)
        Spacer(minLength: 0)
      } else if scrolls {
        ScrollView { content }
      } else {
        GeometryReader { _ in content.fixedSize(horizontal: false, vertical: true) }.clipped()
      }
      OnboardingDots(page: page, select: select)
        .padding(.bottom, 12)
      button
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }
  }

  private var content: some View {
    VStack(spacing: 24) {
      Orb(level: 0, phase: .resting, time: orbTime)
        .frame(width: orbSide, height: orbSide)
        .padding(.top, 24)
        .accessibilityHidden(true)
      VStack(spacing: 16) {
        if let title = page.title {
          Text(title)
            .font(Typography.display)
            .foregroundStyle(Palette.ink)
            .accessibilityAddTraits(.isHeader)
        }
        Text(page.text)
          .font(Typography.body)
          .foregroundStyle(Palette.ink)
      }
      .multilineTextAlignment(.center)
      .padding(.horizontal, 32)
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, 24)
  }

  private var orbSide: CGFloat { typeSize.isAccessibilitySize ? 96 : 160 }

  @ViewBuilder private var button: some View {
    if let next = page.next {
      Button("Next") { select(next) }
        .buttonStyle(.amber)
        .accessibilityIdentifier("onboarding.next")
    } else {
      Button("Start") { start() }
        .buttonStyle(.amber)
        .disabled(isStarting)
        .accessibilityLabel("Start a session")
        .accessibilityIdentifier("onboarding.start")
    }
  }
}

/// One dot per page, read by VoiceOver as one adjustable element.
struct OnboardingDots: View {
  var page: OnboardingPage
  var select: @MainActor (OnboardingPage) -> Void

  var body: some View {
    HStack(spacing: 10) {
      ForEach(OnboardingPage.allCases, id: \.self) { candidate in
        Circle()
          .fill(candidate == page ? Palette.accent : Palette.inkDim)
          .frame(width: 8, height: 8)
      }
    }
    .frame(minHeight: 44)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Page")
    .accessibilityValue("\(page.number) of \(OnboardingPage.allCases.count)")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: if let next = page.next { select(next) }
      case .decrement: if let previous = page.previous { select(previous) }
      @unknown default: break
      }
    }
  }
}
