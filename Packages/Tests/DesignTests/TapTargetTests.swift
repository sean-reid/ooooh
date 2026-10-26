#if canImport(UIKit)
  import SwiftUI
  import Testing
  import UIKit

  @testable import Design

  /// A Button's hit area is its label's size, so the label is what has to reach 44 pt.
  @MainActor
  @Suite struct TapTargetTests {
    @Test func aShortLabelGrowsToFortyFour() {
      let bare = size(of: Text("Done").font(.caption2))
      let target = size(of: Text("Done").font(.caption2).tapTarget())
      #expect(bare.height < 44)
      #expect(bare.width < 44)
      #expect(target.width >= 44)
      #expect(target.height >= 44)
    }

    @Test func aWideLabelKeepsItsWidth() {
      let bare = size(of: Text("Restore purchases"))
      let target = size(of: Text("Restore purchases").tapTarget(alignment: .leading))
      #expect(target.width == bare.width)
      #expect(target.height >= 44)
    }

    private func size(of view: some View) -> CGSize {
      UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 320, height: 320))
    }
  }
#endif
