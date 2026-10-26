import Foundation
import SwiftUI
import Testing

@testable import Design

/// What the site mirrors in orb-geometry.mjs, orb-tokens.mjs, and site.css: the orb and palette
/// constants both runtimes draw from. Phases, ash, dim, the grain tile, and --line stay on one side.
struct DesignTokens: Codable, Equatable {
  struct Geometry: Codable, Equatable {
    var pointCount: Int
    var wobble: [[Double]]
    var voice: [Double]
  }

  struct Tint: Codable, Equatable {
    var core: [Int]
    var warm: [Int]
    var amber: [Int]
    var rim: [Int]
    var glow: [Int]
    var glowAlpha: Double
    var glowBlend: String
    var sheen: Double
    var rimStart: Double
  }

  struct Layers: Codable, Equatable {
    struct Halo: Codable, Equatable {
      var radius: Double
      var clock: Double
      var drift: Double
      var blur: Double
      var start: Double
    }
    struct Under: Codable, Equatable {
      var radius: Double
      var blur: Double
    }
    struct Core: Codable, Equatable {
      var x: Double
      var y: Double
      var end: Double
      var warm: Double
    }
    struct Sheen: Codable, Equatable {
      var blur: Double
      var width: Double
      var height: Double
      var floor: Double
      var glow: Double
    }
    struct Grain: Codable, Equatable {
      var alpha: Double
      var end: Double
    }
    var body: Double
    var breathGrow: Double
    var halo: Halo
    var haloStops: [[Double]]
    var under: Under
    var underStops: [[Double]]
    var core: Core
    var sheen: Sheen
    var grain: Grain
    var grainFade: [[Double]]
  }

  struct Pose: Codable, Equatable {
    var glow: Double
    var drift: Double
    var speed: Double
  }

  struct Motion: Codable, Equatable {
    var riseTau: Double
    var fallTau: Double
    var poseTau: Double
    var resting: Pose
    var still: Pose
  }

  struct Swatch: Codable, Equatable {
    var rgb: [Int]
    var alpha: Double
  }

  var geometry: Geometry
  var tints: [String: Tint]
  var layers: Layers
  var motion: Motion
  var palette: [String: [String: Swatch]]

  static func current() -> DesignTokens {
    let shades = [
      "sky": Palette.skyShades, "skyRaised": Palette.skyRaisedShades, "ink": Palette.inkShades,
      "inkDim": Palette.inkDimShades, "accent": Palette.accentShades,
      "amber": Palette.amberShades,
    ]
    let halo = OrbLayers.halo
    let core = OrbLayers.core
    let sheen = OrbLayers.sheen
    return DesignTokens(
      geometry: Geometry(
        pointCount: OrbGeometry.count, wobble: OrbGeometry.wobble.map(quad),
        voice: quad(OrbGeometry.voice)),
      tints: ["dark": tint(.dark), "light": tint(.light)],
      layers: Layers(
        body: OrbLayers.body, breathGrow: OrbLayers.breathGrow,
        halo: .init(
          radius: halo.radius, clock: halo.clock, drift: halo.drift, blur: halo.blur,
          start: halo.start),
        haloStops: pairs(OrbLayers.haloStops),
        under: .init(radius: OrbLayers.under.radius, blur: OrbLayers.under.blur),
        underStops: pairs(OrbLayers.underStops),
        core: .init(x: core.x, y: core.y, end: core.end, warm: core.warm),
        sheen: .init(
          blur: sheen.blur, width: sheen.width, height: sheen.height, floor: sheen.floor,
          glow: sheen.glow),
        grain: .init(alpha: OrbLayers.grain.alpha, end: OrbLayers.grain.end),
        grainFade: pairs(OrbLayers.grainFade)),
      motion: Motion(
        riseTau: OrbMotion.riseTau, fallTau: OrbMotion.fallTau, poseTau: OrbMotion.poseTau,
        resting: pose(.target(for: .resting)), still: pose(.still)),
      palette: [
        "dark": shades.mapValues { swatch($0.dark) },
        "light": shades.mapValues { swatch($0.light) },
      ])
  }

  private static func quad(
    _ term: (amplitude: Double, harmonic: Double, rate: Double, phase: Double)
  ) -> [Double] {
    [term.amplitude, term.harmonic, term.rate, term.phase]
  }

  private static func pairs(_ stops: [(location: Double, alpha: Double)]) -> [[Double]] {
    stops.map { [$0.location, $0.alpha] }
  }

  private static func tint(_ scheme: ColorScheme) -> Tint {
    let tint = OrbTint(scheme)
    return Tint(
      core: bytes(tint.core), warm: bytes(tint.warm), amber: bytes(tint.amber),
      rim: bytes(tint.rim), glow: bytes(tint.glow), glowAlpha: tint.glowAlpha,
      glowBlend: tint.glowBlend == .multiply ? "multiply" : "source-over", sheen: tint.sheen,
      rimStart: tint.rimStart)
  }

  private static func pose(_ pose: OrbPose) -> Pose {
    Pose(glow: pose.glow, drift: pose.drift, speed: pose.speed)
  }

  private static func swatch(_ shade: Palette.Shade) -> Swatch {
    Swatch(rgb: bytes(shade), alpha: shade.alpha)
  }

  private static func bytes(_ shade: Palette.Shade) -> [Int] {
    [shade.red, shade.green, shade.blue].map { Int(($0 * 255).rounded()) }
  }
}

@Suite struct DesignTokenTests {
  /// WRITE_DESIGN_TOKENS=1 rewrites the fixture site/design-tokens.test.mjs reads.
  @Test func tokensMatchTheFixtureTheSiteReads() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let current = try encoder.encode(DesignTokens.current()) + Data("\n".utf8)
    if ProcessInfo.processInfo.environment["WRITE_DESIGN_TOKENS"] != nil {
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "Fixtures/design-tokens.json")
      try current.write(to: url)
      return
    }
    let url = try #require(
      Bundle.module.url(
        forResource: "design-tokens", withExtension: "json", subdirectory: "Fixtures"))
    let recorded = try JSONDecoder().decode(DesignTokens.self, from: Data(contentsOf: url))
    let normalized = try encoder.encode(recorded) + Data("\n".utf8)
    #expect(
      String(decoding: current, as: UTF8.self) == String(decoding: normalized, as: UTF8.self))
  }
}
