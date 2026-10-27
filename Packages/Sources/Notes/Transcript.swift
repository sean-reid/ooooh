import Foundation
import Transcription

extension Segment {
  /// The start as m:ss. Minutes run past 59, so a long session reads 75:02.
  public var stamp: String {
    let total = Int(max(0, start).rounded(.down))
    return "\(total / 60):" + String(format: "%02d", total % 60)
  }
}

extension [Segment] {
  /// One line per utterance, stamped, under its own heading. Empty for an empty transcript.
  public var markdown: String {
    guard !isEmpty else { return "" }
    return "\n## Transcript\n\n" + map { "\($0.stamp) \($0.text)\n" }.joined()
  }
}
