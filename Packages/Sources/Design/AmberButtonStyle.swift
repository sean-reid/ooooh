import SwiftUI

/// The one filled button: amber capsule, dark text, 56 pt tall, full width.
public struct AmberButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .frame(maxWidth: .infinity, minHeight: 56)
      .foregroundStyle(Palette.inkOnAmber)
      .background(Palette.amber, in: Capsule())
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
  }
}

extension ButtonStyle where Self == AmberButtonStyle {
  public static var amber: AmberButtonStyle { AmberButtonStyle() }
}
