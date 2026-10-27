import Foundation
import Transcription

/// One line of a synthetic script, as fixtures/synthetic/scripts/script.schema.json defines it.
public struct ScriptUtterance: Codable, Equatable, Sendable {
  public var text: String
  public var pauseAfter: TimeInterval
  public var label: String?
  public var note: String?

  public init(text: String, pauseAfter: TimeInterval, label: String? = nil, note: String? = nil) {
    self.text = text
    self.pauseAfter = pauseAfter
    self.label = label
    self.note = note
  }
}

public struct Script: Codable, Equatable, Sendable {
  public var name: String
  public var summary: String
  public var utterances: [ScriptUtterance]

  public init(name: String, summary: String, utterances: [ScriptUtterance]) {
    self.name = name
    self.summary = summary
    self.utterances = utterances
  }
}

/// Where each script utterance landed in a recognizer's transcript of its audio, and the
/// script's labels moved to the end of the segment that holds each labeled line's last word.
/// Words align by longest common subsequence, so order is kept and a misheard word is skipped.
public struct ScriptAlignment: Equatable, Sendable {
  public struct Match: Equatable, Sendable {
    public var utterance: Int
    /// Segments holding this utterance's words, ascending; empty when none matched.
    public var segments: [Int]
    public var words: Int
    public var matched: Int
  }

  public struct Dropped: Equatable, Sendable {
    public var segment: Int
    public var kind: String
    public var utterance: Int
    public var keptKind: String
  }

  public var matches: [Match]
  public var labels: Labels
  /// Segments that hold words from more than one script utterance.
  public var merged: [(segment: Int, utterances: [Int])] {
    var holders: [Int: [Int]] = [:]
    for match in matches {
      for segment in match.segments { holders[segment, default: []].append(match.utterance) }
    }
    return holders.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }
      .map { (segment: $0.key, utterances: $0.value.sorted()) }
  }
  /// Script utterances whose words span more than one segment.
  public var split: [Match] { matches.filter { $0.segments.count > 1 } }
  public var unmatched: [Int] { matches.filter { $0.segments.isEmpty }.map(\.utterance) }
  public var dropped: [Dropped]
  public var scriptWords: Int { matches.reduce(0) { $0 + $1.words } }
  public var matchedWords: Int { matches.reduce(0) { $0 + $1.matched } }
  public var recognizedWords: Int
  public var segments: Int

  public static func == (lhs: ScriptAlignment, rhs: ScriptAlignment) -> Bool {
    lhs.matches == rhs.matches && lhs.labels == rhs.labels && lhs.dropped == rhs.dropped
      && lhs.recognizedWords == rhs.recognizedWords && lhs.segments == rhs.segments
  }

  public static func align(_ script: Script, to segments: [Segment]) -> ScriptAlignment {
    let scriptWords = script.utterances.enumerated().flatMap { index, utterance in
      tokens(utterance.text).map { (utterance: index, word: $0) }
    }
    let recognized = segments.enumerated().flatMap { index, segment in
      tokens(segment.text).map { (segment: index, word: $0) }
    }
    let pairs = commonSubsequence(scriptWords.map(\.word), recognized.map(\.word))
    var hits: [Int: [Int]] = [:]
    for (a, b) in pairs {
      hits[scriptWords[a].utterance, default: []].append(recognized[b].segment)
    }
    let matches = script.utterances.indices.map { index in
      let found = hits[index] ?? []
      return Match(
        utterance: index, segments: Array(Set(found)).sorted(),
        words: tokens(script.utterances[index].text).count,
        matched: found.count)
    }
    var placed: [Int: (kind: String, utterance: Int)] = [:]
    var dropped: [Dropped] = []
    for (index, utterance) in script.utterances.enumerated() {
      guard let kind = utterance.label else { continue }
      let segment = landing(of: index, in: matches, count: segments.count)
      if let previous = placed[segment] {
        dropped.append(
          Dropped(
            segment: segment, kind: previous.kind, utterance: previous.utterance, keptKind: kind))
      }
      placed[segment] = (kind, index)
    }
    let labels = placed.sorted { $0.key < $1.key }.map { segment, label in
      Labels.Label(utterance: segment, at: segments[segment].end, kind: label.kind)
    }
    return ScriptAlignment(
      matches: matches, labels: Labels(fixture: script.name, labels: labels), dropped: dropped,
      recognizedWords: recognized.count, segments: segments.count)
  }

  /// The segment whose pause follows the utterance: the one holding its last matched word, or
  /// for an utterance nothing matched, the last segment of the nearest matched line before it.
  static func landing(of utterance: Int, in matches: [Match], count: Int) -> Int {
    if let last = matches[utterance].segments.last { return last }
    if let before = matches[..<utterance].last(where: { !$0.segments.isEmpty })?.segments.last {
      return before
    }
    if let after = matches[utterance...].first(where: { !$0.segments.isEmpty })?.segments.first {
      return max(0, after - 1)
    }
    return max(0, count - 1)
  }

  /// Lower-case words with punctuation stripped, so "Okay," and "okay" are the same word.
  static func tokens(_ text: String) -> [String] {
    text.lowercased().split(whereSeparator: \.isWhitespace).compactMap { word in
      let kept = word.filter { $0.isLetter || $0.isNumber || $0 == "'" }
      return kept.isEmpty ? nil : String(kept)
    }
  }

  /// Index pairs of a longest common subsequence, ascending on both sides.
  static func commonSubsequence(_ a: [String], _ b: [String]) -> [(Int, Int)] {
    let n = a.count
    let m = b.count
    guard n > 0, m > 0 else { return [] }
    var table = [Int32](repeating: 0, count: (n + 1) * (m + 1))
    let width = m + 1
    for i in stride(from: n - 1, through: 0, by: -1) {
      for j in stride(from: m - 1, through: 0, by: -1) {
        table[i * width + j] =
          a[i] == b[j]
          ? table[(i + 1) * width + j + 1] + 1
          : max(table[(i + 1) * width + j], table[i * width + j + 1])
      }
    }
    var pairs: [(Int, Int)] = []
    var i = 0
    var j = 0
    while i < n, j < m {
      if a[i] == b[j] {
        pairs.append((i, j))
        i += 1
        j += 1
      } else if table[(i + 1) * width + j] >= table[i * width + j + 1] {
        i += 1
      } else {
        j += 1
      }
    }
    return pairs
  }

  /// The merge and split report, one line per finding.
  public var report: [String] {
    var lines = [
      "script \(matches.count) utterances, \(scriptWords) words; recognized \(segments) segments, "
        + "\(recognizedWords) words; \(matchedWords) matched"
        + (scriptWords == 0 ? "" : " (\(matchedWords * 100 / scriptWords)%)")
    ]
    for match in split {
      lines.append(
        "split: utterance \(match.utterance) across segments \(match.segments.first!)-\(match.segments.last!)"
      )
    }
    for merge in merged {
      lines.append(
        "merged: segment \(merge.segment) holds utterances \(merge.utterances.map(String.init).joined(separator: ", "))"
      )
    }
    for utterance in unmatched { lines.append("unmatched: utterance \(utterance)") }
    for drop in dropped {
      lines.append(
        "dropped: \(drop.kind) from utterance \(drop.utterance), segment \(drop.segment) keeps \(drop.keptKind)"
      )
    }
    lines.append("labels: \(labels.labels.count) placed, \(dropped.count) dropped")
    return lines
  }
}
