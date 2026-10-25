import SwiftUI

/// Shown when Start was refused a permission: what is missing and the way to Settings.
public struct PermissionRecoveryScreen: View {
  public var denial: CaptureDenial
  public var orbTime: TimeInterval?
  public var openSettings: @MainActor () -> Void
  /// ImageRenderer draws a ScrollView empty, so snapshots render the content unscrolled.
  var scrolls = true

  @Environment(\.dynamicTypeSize) private var typeSize

  public init(
    denial: CaptureDenial, orbTime: TimeInterval? = nil,
    openSettings: @escaping @MainActor () -> Void
  ) {
    self.denial = denial
    self.orbTime = orbTime
    self.openSettings = openSettings
  }

  public var body: some View {
    VStack(spacing: 0) {
      if scrolls {
        ScrollView { content }
      } else {
        GeometryReader { _ in content.fixedSize(horizontal: false, vertical: true) }.clipped()
      }
      Button("Open Settings") { openSettings() }
        .buttonStyle(.amber)
        .accessibilityIdentifier("onboarding.settings")
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }
  }

  private var content: some View {
    VStack(spacing: 24) {
      Orb(level: 0, phase: .offline, time: orbTime)
        .frame(width: orbSide, height: orbSide)
        .padding(.top, 24)
        .accessibilityHidden(true)
      VStack(spacing: 16) {
        Text(denial.title)
          .font(Typography.title)
          .accessibilityAddTraits(.isHeader)
        Text(denial.text)
          .font(Typography.body)
      }
      .foregroundStyle(Palette.ink)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 32)
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, 24)
  }

  private var orbSide: CGFloat { typeSize.isAccessibilitySize ? 96 : 160 }
}
