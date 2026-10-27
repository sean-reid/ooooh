import SnapshotTesting
import SwiftUI
import TestSupport
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
    assertSnapshot(of: image, as: .pixels, named: "402-\(scheme.name)")

    transcriber.finishDownload()
    await starting.value
    await controller.end()
  }
}
