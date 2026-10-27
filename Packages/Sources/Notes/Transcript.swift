import Foundation
import Transcription

/// Seconds as m:ss. Minutes run past 59, so a long session reads 75:02.
public func stamp(_ seconds: TimeInterval) -> String {
  let total = Int(max(0, seconds).rounded(.down))
  return "\(total / 60):" + String(format: "%02d", total % 60)
}

extension Segment {
  /// The start as m:ss.
  public var stamp: String { Notes.stamp(start) }
}

extension [Segment] {
  /// One line per utterance, stamped, under its own heading, with what the app asked in place
  /// as `m:ss [kind] text`, `marked bad` joining the kind when set. Empty for an empty transcript.
  public func markdown(lines: [SpokenLine] = []) -> String {
    guard !isEmpty || !lines.isEmpty else { return "" }
    return "\n## Transcript\n\n"
      + interleaved(with: lines).map { entry in
        switch entry {
        case .said(let segment): "\(segment.stamp) \(segment.text)\n"
        case .asked(let line): "\(line.stamp) [\(line.markdownTag)] \(line.text)\n"
        }
      }.joined()
  }
}

extension SpokenLine {
  var markdownTag: String { bad ? "\(kind.name), marked bad" : kind.name }
}
