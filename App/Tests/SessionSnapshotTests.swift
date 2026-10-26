import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import ooooh

/// Reference PNGs live in __Snapshots__ and are rendered on the iPhone 17 Pro simulator.
@MainActor
@Suite struct SessionSnapshotTests {
  @Test(arguments: [ColorScheme.dark, .light])
  func downloading(scheme: ColorScheme) async {
    let transcriber = DownloadingTranscriber(fractions: [0.5])
    let controller = SessionController(environment: downloadEnvironment(transcriber))
    let starting = Task { await controller.start(.microphone) }
    transcriber.release()
    await wait { controller.stage == .downloading && controller.downloadProgress == 0.5 }

    let image = render(SessionView(controller: controller, orbTime: 4.2), scheme: scheme)
    assertSnapshot(
      of: image, as: .image(precision: 0.999, perceptualPrecision: 0.97),
      named: "402-\(scheme == .dark ? "dark" : "light")")

    transcriber.finishDownload()
    await starting.value
    await controller.end()
  }

  private func render(
    _ view: some View, width: CGFloat = 402, height: CGFloat = 874, scheme: ColorScheme
  ) -> UIImage {
    let renderer = ImageRenderer(
      content: view.frame(width: width, height: height).environment(\.colorScheme, scheme)
        .dynamicTypeSize(.large))
    renderer.scale = 2
    renderer.proposedSize = ProposedViewSize(width: width, height: height)
    return renderer.uiImage ?? UIImage()
  }
}
