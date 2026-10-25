#if canImport(UIKit)
  import SwiftUI
  import UIKit

  /// Rasterizes a view at 2x the way the snapshot suites compare it.
  @MainActor
  func render(
    _ view: some View, width: CGFloat, height: CGFloat, scheme: ColorScheme,
    type: DynamicTypeSize = .large
  ) -> UIImage {
    let renderer = ImageRenderer(
      content: view.frame(width: width, height: height).environment(\.colorScheme, scheme)
        .dynamicTypeSize(type))
    renderer.scale = 2
    renderer.proposedSize = ProposedViewSize(width: width, height: height)
    return renderer.uiImage ?? UIImage()
  }

  extension ColorScheme {
    var name: String { self == .dark ? "dark" : "light" }
  }
#endif
