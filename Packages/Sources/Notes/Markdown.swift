import Foundation

extension SessionNotes {
  public func markdown(date: Date, calendar: Calendar = .current) -> String {
    var out = "# \(title)\n\n"
    out += date.formatted(.dateTime.year().month(.wide).day().locale(Locale(identifier: "en_US")))
    out += "\n"
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
