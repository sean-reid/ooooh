import Foundation

/// Collects a live session into a replayable fixture: final segments as JSON, the microphone audio as CAF beside it.
public actor FixtureRecorder {
  public nonisolated let fixtureURL: URL
  public nonisolated let audioURL: URL
  public nonisolated let audio: AudioFileWriter
  private var segments: [Segment] = []

  public init(directory: URL, sessionStart: Date = .now, timeZone: TimeZone = .current) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let base = Self.baseName(for: sessionStart, timeZone: timeZone)
    fixtureURL = directory.appending(path: "\(base).json")
    audioURL = directory.appending(path: "\(base).caf")
    audio = AudioFileWriter(url: audioURL)
  }

  public var finalCount: Int { segments.count }

  public func record(_ event: TranscriptEvent) {
    guard case .segment(let segment) = event, segment.isFinal else { return }
    segments.append(segment)
  }

  @discardableResult
  public func finish() throws -> FixtureTranscriber.Fixture {
    try audio.close()
    let fixture = FixtureTranscriber.Fixture(segments: segments.sorted { $0.start < $1.start })
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(fixture).write(to: fixtureURL, options: .atomic)
    return fixture
  }

  static func baseName(for date: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    return formatter.string(from: date)
  }
}
