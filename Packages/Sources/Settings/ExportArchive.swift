import CoreTransferable
import Foundation
import Persistence
import UniformTypeIdentifiers

/// Every session as Markdown, one file each, plus a README, ready to zip.
public struct ExportArchive: Sendable, Equatable {
  public struct File: Sendable, Equatable {
    public var name: String
    public var contents: String
  }

  public var files: [File]
  public var exportedAt: Date
  public var timeZone: TimeZone

  /// Names each session `yyyy-MM-dd <title>.md`, from the stamp the store put on the
  /// document and the heading on its first line. A repeated name gets a counter.
  public init(documents: [MarkdownDocument], exportedAt: Date, timeZone: TimeZone = .current) {
    self.exportedAt = exportedAt
    self.timeZone = timeZone
    let readme = Self.readme(count: documents.count, exportedAt, timeZone)
    var files = [File(name: "README.md", contents: readme)]
    var taken: Set<String> = ["README.md"]
    for document in documents {
      let base = "\(Self.day(of: document)) \(Self.title(of: document))"
      var name = "\(base).md"
      var copy = 1
      while taken.contains(name) {
        copy += 1
        name = "\(base) \(copy).md"
      }
      taken.insert(name)
      files.append(File(name: name, contents: document.contents))
    }
    self.files = files
  }

  public var filename: String {
    "ooooh export \(Self.dayFormatter(timeZone).string(from: exportedAt)).zip"
  }

  public func zipData() -> Data {
    ZipWriter.archive(
      files.map { ZipWriter.Entry(name: $0.name, data: Data($0.contents.utf8)) },
      modified: exportedAt, timeZone: timeZone)
  }

  static func readme(count: Int, _ exportedAt: Date, _ timeZone: TimeZone) -> String {
    var style = Date.FormatStyle.dateTime.year().month(.wide).day()
    style.timeZone = timeZone
    style.locale = Locale(identifier: "en_US")
    let sessions = count == 1 ? "1 session" : "\(count) sessions"
    return "# ooooh\n\nExported from the ooooh app on \(exportedAt.formatted(style)). "
      + "\(sessions), one Markdown file each, named by date and title.\n"
  }

  static func day(of document: MarkdownDocument) -> String {
    let stamp = document.filename.prefix(10)
    let shape = stamp.enumerated().allSatisfy { index, character in
      index == 4 || index == 7 ? character == "-" : character.isNumber
    }
    return stamp.count == 10 && shape ? String(stamp) : "undated"
  }

  static func title(of document: MarkdownDocument) -> String {
    let heading = document.contents.split(separator: "\n", maxSplits: 1).first ?? ""
    let raw = heading.hasPrefix("# ") ? heading.dropFirst(2) : heading
    let banned: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
    let words = raw.filter { !banned.contains($0) && !$0.isNewline }.split(separator: " ")
    let title = words.joined(separator: " ").prefix(80).trimmingCharacters(in: .whitespaces)
    return title.isEmpty ? "Untitled" : title
  }

  static func dayFormatter(_ timeZone: TimeZone) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }
}

/// What the share sheet receives. The zip is built when the sheet asks for it.
public struct ExportFile: Transferable, Sendable {
  var store: SessionStore

  public init(store: SessionStore) {
    self.store = store
  }

  public static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .zip) { file in
      SentTransferredFile(try await file.write(), allowAccessingOriginalFile: false)
    }
  }

  /// The one place an export zip sits while the share sheet copies it.
  static let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "ooooh-export", isDirectory: true)

  /// Writes the zip over the last export and returns its URL.
  public func write(exportedAt: Date = .now) async throws -> URL {
    let archive = ExportArchive(documents: try await store.exportMarkdown(), exportedAt: exportedAt)
    Self.removeExports()
    try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
    let url = Self.directory.appendingPathComponent(archive.filename)
    try archive.zipData().write(to: url)
    return url
  }

  /// Deletes the last export zip. Runs at launch, when Settings closes, and after a delete.
  public static func removeExports() {
    try? FileManager.default.removeItem(at: directory)
  }
}
