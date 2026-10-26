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
      .foregroundStyle(foreground)
      .background(fill, in: Capsule())
      .overlay(Capsule().strokeBorder(Palette.amberDim, lineWidth: look == .outlined ? 1 : 0))
      .opacity(configuration.isPressed ? 0.8 : 1)
  }

  /// Disabled keeps the label at full strength and pales the fill instead, so the words stay
  /// above 3:1 on the paper.
  private var foreground: Color {
    switch look {
    case .filled: isEnabled ? Palette.inkOnAmber : Palette.ink
    case .outlined: isEnabled ? Palette.ink : Palette.inkDim
    }
  }

  private var fill: Color {
    switch look {
    case .filled: isEnabled ? Palette.amber : Palette.amberDim
    case .outlined: Palette.skyRaised
    }
  }
}

extension ButtonStyle where Self == AmberButtonStyle {
  public static var amber: AmberButtonStyle { AmberButtonStyle() }
  public static var amberOutlined: AmberButtonStyle { AmberButtonStyle(look: .outlined) }
}
