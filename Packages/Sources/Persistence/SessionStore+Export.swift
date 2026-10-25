import Foundation
import Notes
import SwiftData

extension SessionStore {
  /// One Markdown file per session, oldest first, named from the start time and the title.
  public func exportMarkdown(timeZone: TimeZone = .current) throws -> [MarkdownDocument] {
    let descriptor = FetchDescriptor<StoredSession>(sortBy: [SortDescriptor(\.startedAt)])
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    return try modelContext.fetch(descriptor).map { session in
      let notes =
        Self.notes(of: session, items: Self.entries(of: session))
        ?? SessionNotes(title: session.title)
      let stamp = formatter.string(from: session.startedAt)
      let slug = Self.filenameSlug(session.title)
      return MarkdownDocument(
        filename: slug.isEmpty ? "\(stamp).md" : "\(stamp)-\(slug).md",
        contents: notes.markdown(date: session.startedAt, timeZone: timeZone))
    }
  }

  static func filenameSlug(_ title: String) -> String {
    let words = title.lowercased().split { !$0.isLetter && !$0.isNumber }
    return words.prefix(8).joined(separator: "-")
  }
}
