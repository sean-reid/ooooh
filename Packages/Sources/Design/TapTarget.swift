import SwiftUI

extension View {
  /// The 44 pt minimum for a text button. Goes on the label inside a Button or Link; on the
  /// Button itself the frame grows but the hit area stays the text's size.
  public func tapTarget(alignment: Alignment = .center) -> some View {
    frame(minWidth: 44, minHeight: 44, alignment: alignment)
  }
}
