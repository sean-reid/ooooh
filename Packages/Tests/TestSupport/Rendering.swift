#if canImport(UIKit)
  import SnapshotTesting
  import SwiftUI
  import UIKit

  /// Rasterizes a view at 2x the way every snapshot suite compares it. A nil height takes the
  /// content's own; `alignment` places content that overflows a fixed height.
  @MainActor
  public func render(
    _ view: some View, width: CGFloat = 402, height: CGFloat? = 874, scheme: ColorScheme,
    type: DynamicTypeSize = .large, alignment: Alignment = .center
  ) -> UIImage {
    let renderer = ImageRenderer(
      content: view.frame(width: width, height: height, alignment: alignment).clipped()
        .environment(\.colorScheme, scheme).dynamicTypeSize(type))
    renderer.scale = 2
    renderer.proposedSize = ProposedViewSize(width: width, height: height)
    return renderer.uiImage ?? UIImage()
  }

  /// A phone size the screens are snapshotted at, named by its point width.
  public struct Device: Sendable {
    public let name: String
    public let width: CGFloat
    public let height: CGFloat

    public static let small = Device(name: "375", width: 375, height: 667)
    public static let phone = Device(name: "402", width: 402, height: 874)
    public static let large = Device(name: "440", width: 440, height: 956)
    public static let all = [small, phone, large]
    public static let extremes = [small, large]
  }

  extension ColorScheme {
    public var name: String { self == .dark ? "dark" : "light" }
  }

  extension Snapshotting where Value == UIImage, Format == UIImage {
    /// The tolerance every PNG in the repo was recorded at.
    public static var pixels: Snapshotting {
      .image(precision: 0.999, perceptualPrecision: 0.97)
    }
  }
#endif
