import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Night sky by default, pale warm paper in light mode. One accent, nothing else saturated.
public enum Palette {
  static let skyShades = Shades(light: Shade(0.957, 0.937, 0.902), dark: Shade(0.047, 0.051, 0.067))
  public static let sky = skyShades.color
  static let skyRaisedShades = Shades(
    light: Shade(0.914, 0.886, 0.835), dark: Shade(0.086, 0.090, 0.110))
  public static let skyRaised = skyRaisedShades.color
  static let amberShade = Shade(0.980, 0.741, 0.345)
  static let amberShades = Shades(light: amberShade, dark: amberShade)
  public static let amber = amberShades.color
  static let amberDimShades = Shades(light: amberShade.alpha(0.35), dark: amberShade.alpha(0.35))
  public static let amberDim = amberDimShades.color
  /// Amber as text, a glyph, or a tint: deeper on the paper so it clears 4.5:1 against the sky.
  static let accentShades = Shades(light: Shade(0.612, 0.306, 0.027), dark: amberShade)
  public static let accent = accentShades.color
  /// Text on an amber fill, dark in both schemes.
  static let inkOnAmberShades = Shades(
    light: Shade(0.118, 0.102, 0.078), dark: Shade(0.047, 0.051, 0.067))
  public static let inkOnAmber = inkOnAmberShades.color
  static let inkShades = Shades(light: Shade(0.118, 0.102, 0.078), dark: Shade(0.925, 0.914, 0.886))
  public static let ink = inkShades.color
  static let inkDimShades = Shades(
    light: inkShades.light.alpha(0.68), dark: inkShades.dark.alpha(0.6))
  public static let inkDim = inkDimShades.color

  struct Shade {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) {
      self.red = red
      self.green = green
      self.blue = blue
      self.alpha = alpha
    }

    func alpha(_ alpha: Double) -> Shade {
      Shade(red, green, blue, alpha: alpha)
    }

    /// The shade fixed, not adaptive.
    var color: Color {
      Color(red: red, green: green, blue: blue, opacity: alpha)
    }
  }

  /// One shade per appearance, resolved as the scheme changes.
  struct Shades {
    var light: Shade
    var dark: Shade

    var color: Color { adaptive(light: light, dark: dark) }
  }

  static func adaptive(light: Shade, dark: Shade) -> Color {
    #if canImport(UIKit)
      return Color(
        uiColor: UIColor { traits in
          let shade = traits.userInterfaceStyle == .dark ? dark : light
          return UIColor(
            red: shade.red, green: shade.green, blue: shade.blue, alpha: shade.alpha)
        })
    #elseif canImport(AppKit)
      return Color(
        nsColor: NSColor(name: nil) { appearance in
          let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
          let shade = isDark ? dark : light
          return NSColor(
            srgbRed: shade.red, green: shade.green, blue: shade.blue, alpha: shade.alpha)
        })
    #else
      return Color(red: dark.red, green: dark.green, blue: dark.blue).opacity(dark.alpha)
    #endif
  }
}
