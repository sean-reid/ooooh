import Foundation
import State
import Transcription

/// One line the app said in a session, kept with the transcript so it reads back in place.
public struct SpokenLine: Equatable, Sendable, Identifiable {
  public enum Kind: Equatable, Hashable, Sendable {
    case intervention(InterventionKind)
    case finishedQuestion

    public static let finishedName = "finished"

    public var name: String {
      switch self {
      case .intervention(let kind): kind.rawValue
      case .finishedQuestion: Self.finishedName
      }
    }

    public init?(name: String) {
      if name == Self.finishedName {
        self = .finishedQuestion
      } else if let kind = InterventionKind(rawValue: name) {
        self = .intervention(kind)
      } else {
        return nil
      }
    }
  }

  public var id: UUID
  public var text: String
  public var kind: Kind
  /// On the transcript's clock, the moment the pause held and the line was requested.
  public var at: TimeInterval
  /// Aloud through the voice, as opposed to shown through the orb.
  public var spoken: Bool
  /// Stopped before it finished, by speech or by End.
  public var cut: Bool
  public var bad: Bool

  public init(
    id: UUID = UUID(), text: String, kind: Kind, at: TimeInterval, spoken: Bool,
    cut: Bool = false, bad: Bool = false
  ) {
    self.id = id
    self.text = text
    self.kind = kind
    self.at = at
    self.spoken = spoken
    self.cut = cut
    self.bad = bad
  }

  public var stamp: String { Notes.stamp(at) }
}

/// A transcript read in order: what was said and what the app asked.
public enum TranscriptEntry: Equatable, Sendable {
  case said(Segment)
  case asked(SpokenLine)

  public var time: TimeInterval {
    switch self {
    case .said(let segment): segment.start
    case .asked(let line): line.at
    }
  }
}

extension [Segment] {
  /// Segments and lines merged by time. A line on a segment's start goes first: speech at the
  /// due time lets the line speak.
  public func interleaved(with lines: [SpokenLine]) -> [TranscriptEntry] {
    var pending = lines.sorted { $0.at < $1.at }[...]
    var merged: [TranscriptEntry] = []
    merged.reserveCapacity(count + pending.count)
    for segment in self {
      while let line = pending.first, line.at <= segment.start {
        merged.append(.asked(line))
        pending.removeFirst()
      }
      merged.append(.said(segment))
    }
    merged.append(contentsOf: pending.map(TranscriptEntry.asked))
    return merged
  }
}
