import CoreText
import Foundation
import SwiftUI

/// Instrument Serif for display and prompts, SF for everything else. All sizes follow Dynamic Type.
public enum Typography {
  public static var display: Font { serif(.regular, size: 44, relativeTo: .largeTitle) }
  public static var title: Font { serif(.regular, size: 30, relativeTo: .title) }
  public static var prompt: Font { serif(.italic, size: 26, relativeTo: .title2) }
  public static let body = Font.system(.body)
  public static let caption = Font.system(.caption)

  enum Face: String, CaseIterable {
    case regular = "InstrumentSerif-Regular"
    case italic = "InstrumentSerif-Italic"

    var url: URL? {
      Bundle.module.url(forResource: rawValue, withExtension: "ttf", subdirectory: "Fonts")
    }
  }

  static var licenseURL: URL? {
    Bundle.module.url(forResource: "OFL", withExtension: "txt", subdirectory: "Fonts")
  }

  @discardableResult
  static func registerFonts() -> Bool { registration }

  private static let registration: Bool = {
    Face.allCases.allSatisfy { face in
      guard let url = face.url else { return false }
      var error: Unmanaged<CFError>?
      if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
      let code = (error?.takeRetainedValue()).map { CFErrorGetCode($0) }
      return code == CTFontManagerError.alreadyRegistered.rawValue
        || code == CTFontManagerError.duplicatedName.rawValue
    }
  }()

  private static func serif(_ face: Face, size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
    registerFonts()
    return Font.custom(face.rawValue, size: size, relativeTo: style)
  }
}
