import SwiftUI

/// The one filled button: amber capsule, dark text, 56 pt tall, full width. Outlined is the
/// same shape on the raised sky with an amber edge, for the action that undoes a running one.
public struct AmberButtonStyle: ButtonStyle {
  public enum Look: Sendable {
    case filled, outlined
  }

  @Environment(\.isEnabled) private var isEnabled
  var look: Look

  public init(look: Look = .filled) {
    self.look = look
  }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .frame(maxWidth: .infinity, minHeight: 56)
      .foregroundStyle(look == .filled ? Palette.inkOnAmber : Palette.ink)
      .background(look == .filled ? Palette.amber : Palette.skyRaised, in: Capsule())
      .overlay(Capsule().strokeBorder(Palette.amberDim, lineWidth: look == .outlined ? 1 : 0))
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
  }
}

extension ButtonStyle where Self == AmberButtonStyle {
  public static var amber: AmberButtonStyle { AmberButtonStyle() }
  public static var amberOutlined: AmberButtonStyle { AmberButtonStyle(look: .outlined) }
}
