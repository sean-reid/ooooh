import CoreGraphics
import Foundation

/// One seeded tile of gray noise, so every frame and every snapshot sees the same grain.
enum OrbGrain {
  static let tile = 160
  static let image: CGImage? = make()

  private static func make() -> CGImage? {
    var state: UInt64 = 0x6f6f_6f6f_6800_2026
    var bytes = [UInt8](repeating: 0, count: tile * tile)
    for i in bytes.indices {
      state &+= 0x9e37_79b9_7f4a_7c15
      var z = state
      z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
      z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
      z ^= z >> 31
      bytes[i] = UInt8(truncatingIfNeeded: 72 &+ (z >> 56) % 112)
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
    return CGImage(
      width: tile, height: tile, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: tile,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent)
  }
}
