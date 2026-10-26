import SwiftUI
import Testing

@testable import Design

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

@Suite struct DesignTests {
  @Test func everyPhaseNamesTheListener() {
    let labels = Set(OrbPhase.allCases.map(\.accessibilityLabel))
    #expect(labels.count == OrbPhase.allCases.count)
    #expect(labels.allSatisfy { $0.hasPrefix("Your listener") })
    #expect(OrbPhase.resting.accessibilityLabel == "Your listener, resting")
  }

  @Test func bundlesBothFacesAndTheLicense() throws {
    for face in Typography.Face.allCases {
      #expect(face.url != nil, "\(face.rawValue).ttf missing from the Fonts resource")
    }
    let license = try #require(Typography.licenseURL)
    let text = try String(contentsOf: license, encoding: .utf8)
    #expect(text.contains("SIL Open Font License, Version 1.1"))
  }

  @Test func registersFontsOnce() {
    #expect(Typography.registerFonts())
    #expect(Typography.registerFonts())
  }

  @Test func stillFrameTakesThePhaseLook() {
    let frame = OrbMotion.still(at: 3, level: 1.4, phase: .offline)
    #expect(frame.clock == 3)
    #expect(frame.breath == 1)
    #expect(frame.pose.dim == 1)
    #expect(frame.pose.speed == 0)
  }

  @Test @MainActor func restingAtSilenceRestsFromTheFirstFrame() {
    let motion = OrbMotion()
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let first = motion.advance(to: start, level: 0, phase: .resting)
    #expect(motion.rests)
    let later = motion.advance(to: start + 5, level: 0, phase: .resting)
    #expect(later.clock == first.clock)
    #expect(motion.rests)
  }

  @Test @MainActor func restingSettlesAfterListeningAndWakesOnLevel() {
    let motion = OrbMotion()
    let start = Date(timeIntervalSinceReferenceDate: 0)
    _ = motion.advance(to: start, level: 0.3, phase: .listening)
    #expect(!motion.rests)
    var restedAt: TimeInterval?
    var clockAtRest: TimeInterval?
    for tick in 1...120 {
      let time = Double(tick) / 30
      let frame = motion.advance(to: start + time, level: 0, phase: .resting)
      if motion.rests {
        if restedAt == nil {
          restedAt = time
          clockAtRest = frame.clock
        } else {
          #expect(frame.clock == clockAtRest)
        }
      }
    }
    let settled = try! #require(restedAt)
    #expect(settled > 1 && settled < 3, "settled after \(settled) s")
    _ = motion.advance(to: start + 5, level: 0.5, phase: .resting)
    #expect(!motion.rests)
  }

  @Test @MainActor func offlineAtSilenceRestsAndListeningNeverDoes() {
    let motion = OrbMotion()
    let start = Date(timeIntervalSinceReferenceDate: 0)
    _ = motion.advance(to: start, level: 0, phase: .offline)
    #expect(motion.rests)
    for tick in 1...60 {
      _ = motion.advance(to: start + Double(tick) / 30, level: 0, phase: .listening)
    }
    #expect(!motion.rests)
  }

  @Test func blobStaysClosedAndNearItsRadius() {
    let path = OrbGeometry.blob(
      center: .init(x: 100, y: 100), radius: 50, clock: 2.5, drift: 1, breath: 1, stretch: 1.18)
    let box = path.boundingRect
    #expect(box.width > 70 && box.width < 110)
    #expect(box.height > 85 && box.height < 125)
    #expect(path.contains(.init(x: 100, y: 100)))
  }

  @Test(arguments: [ColorScheme.light, .dark])
  func textClearsTheSkyInBothSchemes(scheme: ColorScheme) {
    let text = [("ink", Palette.ink), ("accent", Palette.accent)]
    let skies = [("sky", Palette.sky), ("skyRaised", Palette.skyRaised)]
    for (textName, textColor) in text {
      for (skyName, skyColor) in skies {
        let ratio = contrast(textColor, on: skyColor, in: scheme)
        #expect(ratio >= 4.5, "\(textName) on \(skyName) in \(scheme) is \(ratio):1")
      }
    }
  }

  @Test(arguments: [ColorScheme.light, .dark])
  func inkOnAmberFillsClearsInBothSchemes(scheme: ColorScheme) {
    let ratio = contrast(Palette.inkOnAmber, on: Palette.amber, in: scheme)
    #expect(ratio >= 4.5, "inkOnAmber on amber in \(scheme) is \(ratio):1")
  }

  @Test func amberAloneFailsOnThePaper() {
    #expect(contrast(Palette.amber, on: Palette.sky, in: .light) < 3)
  }

  /// WCAG 2 contrast of two adaptive colors, each resolved for the scheme.
  private func contrast(_ foreground: Color, on background: Color, in scheme: ColorScheme) -> Double
  {
    let lighter = max(luminance(foreground, in: scheme), luminance(background, in: scheme))
    let darker = min(luminance(foreground, in: scheme), luminance(background, in: scheme))
    return (lighter + 0.05) / (darker + 0.05)
  }

  private func luminance(_ color: Color, in scheme: ColorScheme) -> Double {
    let (red, green, blue) = components(of: color, in: scheme)
    func linear(_ channel: Double) -> Double {
      channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  private func components(of color: Color, in scheme: ColorScheme) -> (Double, Double, Double) {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    #if canImport(UIKit)
      let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
      UIColor(color).resolvedColor(with: traits).getRed(
        &red, green: &green, blue: &blue, alpha: &alpha)
    #elseif canImport(AppKit)
      let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
      appearance.performAsCurrentDrawingAppearance {
        NSColor(color).usingColorSpace(.sRGB)!.getRed(
          &red, green: &green, blue: &blue, alpha: &alpha)
      }
    #endif
    return (Double(red), Double(green), Double(blue))
  }
}
