import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders the resting orb as the app icon, from the same painter the indicator uses.
@MainActor
public enum IconRenderer {
  public static let size: CGFloat = 1024
  /// The orb frame overshoots the tile so the body fills about two thirds of it at home screen size.
  public static let orbScale: CGFloat = 1.3
  /// The still frame in the resting-0-0 snapshot.
  public static let time: TimeInterval = 4.2

  public enum Variant: String, CaseIterable, Sendable {
    case light = "AppIcon"
    case dark = "AppIcon-Dark"
    case tinted = "AppIcon-Tinted"
  }

  public static func render(_ variant: Variant) -> CGImage? {
    guard let lit = renderOnSky() else { return nil }
    switch variant {
    case .light: return lit
    case .dark: return Bitmap(lit)?.unmixingBackground().image
    case .tinted: return Bitmap(lit)?.luminanceOverBackground().image
    }
  }

  /// Writes one PNG per variant and the Contents.json Xcode expects, returning the written URLs.
  @discardableResult
  public static func write(to appiconset: URL) throws -> [URL] {
    let files = FileManager.default
    try files.createDirectory(at: appiconset, withIntermediateDirectories: true)
    var written: [URL] = []
    for variant in Variant.allCases {
      guard let image = render(variant) else { throw IconError.renderFailed(variant) }
      let url = appiconset.appendingPathComponent("\(variant.rawValue).png")
      try writePNG(image, to: url)
      written.append(url)
    }
    let contents = appiconset.appendingPathComponent("Contents.json")
    try Data(contentsJSON.utf8).write(to: contents)
    written.append(contents)
    return written
  }

  static let contentsJSON = """
    {
      "images" : [
        {
          "filename" : "AppIcon.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        },
        {
          "appearances" : [
            {
              "appearance" : "luminosity",
              "value" : "dark"
            }
          ],
          "filename" : "AppIcon-Dark.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        },
        {
          "appearances" : [
            {
              "appearance" : "luminosity",
              "value" : "tinted"
            }
          ],
          "filename" : "AppIcon-Tinted.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """

  private static func renderOnSky() -> CGImage? {
    let renderer = ImageRenderer(content: IconView())
    renderer.scale = 1
    renderer.isOpaque = true
    renderer.proposedSize = ProposedViewSize(width: size, height: size)
    return renderer.cgImage
  }

  private static func writePNG(_ image: CGImage, to url: URL) throws {
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw IconError.writeFailed(url) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconError.writeFailed(url) }
  }

  public enum IconError: Error {
    case renderFailed(Variant)
    case writeFailed(URL)
  }
}

struct IconView: View {
  var body: some View {
    ZStack {
      Palette.sky
      Orb(level: 0, phase: .resting, time: IconRenderer.time)
        .frame(
          width: IconRenderer.size * IconRenderer.orbScale,
          height: IconRenderer.size * IconRenderer.orbScale)
    }
    .frame(width: IconRenderer.size, height: IconRenderer.size)
    .clipped()
    .environment(\.colorScheme, .dark)
  }
}

/// Premultiplied RGBA pixels of an opaque render, with the corner pixel taken as the background.
struct Bitmap {
  var width: Int
  var height: Int
  var pixels: [UInt8]

  init?(_ image: CGImage) {
    width = image.width
    height = image.height
    pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer in
      CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ).map { context in
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
      }
    }
    if drawn != true { return nil }
  }

  var image: CGImage? {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  /// Solves P = (1 - a) B + a C for the smallest a that keeps C in range, keeping a C premultiplied.
  func unmixingBackground() -> Bitmap {
    var out = self
    let background = (Double(pixels[0]), Double(pixels[1]), Double(pixels[2]))
    for i in stride(from: 0, to: pixels.count, by: 4) {
      let p = (Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2]))
      let alpha = max(
        0,
        (p.0 - background.0) / (255 - background.0),
        (p.1 - background.1) / (255 - background.1),
        (p.2 - background.2) / (255 - background.2))
      out.pixels[i] = UInt8(max(0, min(255, p.0 - (1 - alpha) * background.0)))
      out.pixels[i + 1] = UInt8(max(0, min(255, p.1 - (1 - alpha) * background.1)))
      out.pixels[i + 2] = UInt8(max(0, min(255, p.2 - (1 - alpha) * background.2)))
      out.pixels[i + 3] = UInt8(alpha * 255)
    }
    return out
  }

  /// White at brightness-as-alpha over transparent, which is what the tinted appearance expects.
  func luminanceOverBackground() -> Bitmap {
    var out = self
    let floor = luma(at: 0)
    for i in stride(from: 0, to: pixels.count, by: 4) {
      let value = UInt8(max(0, (luma(at: i) - floor) / (255 - floor)) * 255)
      out.pixels[i] = value
      out.pixels[i + 1] = value
      out.pixels[i + 2] = value
      out.pixels[i + 3] = value
    }
    return out
  }

  private func luma(at i: Int) -> Double {
    0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
  }
}
