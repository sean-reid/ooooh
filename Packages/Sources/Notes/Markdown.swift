import Foundation
import Transcription

extension SessionNotes {
  /// The notes as Markdown, with the transcript as the last section when one is given.
  public func markdown(
    date: Date, timeZone: TimeZone = .current, transcript: [Segment] = [],
    lines: [SpokenLine] = []
  ) -> String {
    var style = Date.FormatStyle.dateTime.year().month(.wide).day()
    style.timeZone = timeZone
    style.locale = Locale(identifier: "en_US")
    var out = "# \(title)\n\n" + date.formatted(style) + "\n"
    if let summary { out += "\n" + summary + "\n" }
    for (section, items) in sections {
      out += "\n## \(section.title)\n\n"
      for item in items {
        let mark = item.resolved ? "- [x] " : "- "
        out += mark + item.text + "\n"
      }
    }
    return out + transcript.markdown(lines: lines)
  }
}
