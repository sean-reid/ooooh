import SwiftUI

extension View {
  /// The 44 pt minimum for a text or glyph button. Goes on the label inside a Button or Link; on
  /// the Button itself the frame grows but the hit area stays the text's size. The content shape
  /// makes the whole frame the hit area and the accessibility frame under the plain style too.
  public func tapTarget(alignment: Alignment = .center) -> some View {
    frame(minWidth: 44, minHeight: 44, alignment: alignment).contentShape(Rectangle())
  }
}
