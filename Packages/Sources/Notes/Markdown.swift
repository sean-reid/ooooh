import Foundation

extension SessionNotes {
  public func markdown(date: Date, timeZone: TimeZone = .current) -> String {
    var style = Date.FormatStyle.dateTime.year().month(.wide).day()
    style.timeZone = timeZone
    style.locale = Locale(identifier: "en_US")
    var out = "# \(title)\n\n" + date.formatted(style) + "\n"
    if let summary { out += "\n" + summary + "\n" }
    for section in sections {
      out += "\n## \(section.name)\n\n"
      for item in section.items {
        let mark = item.resolved ? "- [x] " : "- "
        out += mark + item.text + "\n"
      }
    }
    return out
  }
}
