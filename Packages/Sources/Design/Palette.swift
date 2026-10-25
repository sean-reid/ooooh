import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Night sky by default, pale warm paper in light mode. One accent, nothing else saturated.
public enum Palette {
  public static let sky = adaptive(
    light: Shade(0.957, 0.937, 0.902), dark: Shade(0.047, 0.051, 0.067))
  public static let skyRaised = adaptive(
    light: Shade(0.914, 0.886, 0.835), dark: Shade(0.086, 0.090, 0.110))
  public static let amber = adaptive(
    light: Shade(0.980, 0.741, 0.345), dark: Shade(0.980, 0.741, 0.345))
  public static let amberDim = adaptive(
    light: Shade(0.980, 0.741, 0.345, alpha: 0.35), dark: Shade(0.980, 0.741, 0.345, alpha: 0.35))
  public static let ink = adaptive(
    light: Shade(0.118, 0.102, 0.078), dark: Shade(0.925, 0.914, 0.886))
  public static let inkDim = adaptive(
    light: Shade(0.118, 0.102, 0.078, alpha: 0.68), dark: Shade(0.925, 0.914, 0.886, alpha: 0.6))

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
