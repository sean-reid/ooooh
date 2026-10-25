import Foundation
import Governor
import Transcription

/// What tools/labeler exports. One entry per utterance a human marked.
public struct Labels: Codable, Equatable, Sendable {
  public var fixture: String
  public var labels: [Label]

  public init(fixture: String, labels: [Label]) {
    self.fixture = fixture
    self.labels = labels
  }

  public struct Label: Codable, Equatable, Sendable {
    public var utterance: Int
    public var at: TimeInterval
    public var kind: String

    public init(utterance: Int, at: TimeInterval, kind: String) {
      self.utterance = utterance
      self.at = at
      self.kind = kind
    }
  }

  public static let finishedKind = "finished"
  public static let leaveKind = "leave"
}

/// Precision, recall, and lateness of a session's decisions against labels.
public struct EvalReport: Equatable, Sendable {
  public struct Kind: Equatable, Sendable {
    public var truePositives: Int = 0
    public var falsePositives: Int = 0
    public var falseNegatives: Int = 0
    public var latenesses: [Int] = []

    public var precision: Double? {
      let total = truePositives + falsePositives
      return total == 0 ? nil : Double(truePositives) / Double(total)
    }

    public var recall: Double? {
      let total = truePositives + falseNegatives
      return total == 0 ? nil : Double(truePositives) / Double(total)
    }

    public var medianLateness: Double? {
      guard !latenesses.isEmpty else { return nil }
      let sorted = latenesses.sorted()
      let mid = sorted.count / 2
      return sorted.count.isMultiple(of: 2)
        ? Double(sorted[mid - 1] + sorted[mid]) / 2 : Double(sorted[mid])
    }
  }

  public var byKind: [String: Kind]
  public var overall: Kind
  public var finished: Kind
  public var intrusions: Int

  /// How many utterances late a decision may land and still count.
  public static let tolerance = 1

  public static func score(_ result: SessionResult, against labels: Labels) -> EvalReport {
    let ends = result.transcript.map(\.end).sorted()
    func utterancesBetween(_ from: TimeInterval, _ to: TimeInterval) -> Int {
      ends.filter { $0 > from && $0 <= to }.count
    }

    var byKind: [String: Kind] = [:]
    var overall = Kind()
    var finished = Kind()
    var unmatched = labels.labels.filter { $0.kind != Labels.leaveKind }

    func match(at: TimeInterval, kind: String?) -> (Labels.Label, Int)? {
      let candidates = unmatched.enumerated().compactMap { index, label -> (Int, Int)? in
        guard label.at <= at else { return nil }
        if let kind, label.kind != kind { return nil }
        if kind == nil, label.kind == Labels.finishedKind { return nil }
        let late = utterancesBetween(label.at, at)
        return late <= tolerance ? (index, late) : nil
      }
      guard let best = candidates.min(by: { $0.1 < $1.1 }) else { return nil }
      let label = unmatched.remove(at: best.0)
      return (label, best.1)
    }

    for prompt in result.prompts {
      let name = prompt.kind.rawValue
      if let (_, late) = match(at: prompt.at, kind: name) ?? match(at: prompt.at, kind: nil) {
        byKind[name, default: Kind()].truePositives += 1
        byKind[name, default: Kind()].latenesses.append(late)
        overall.truePositives += 1
        overall.latenesses.append(late)
      } else {
        byKind[name, default: Kind()].falsePositives += 1
        overall.falsePositives += 1
      }
    }
    for ask in result.finishedAsks {
      if let (_, late) = match(at: ask, kind: Labels.finishedKind) {
        finished.truePositives += 1
        finished.latenesses.append(late)
      } else {
        finished.falsePositives += 1
      }
    }
    for label in unmatched {
      if label.kind == Labels.finishedKind {
        finished.falseNegatives += 1
      } else {
        byKind[label.kind, default: Kind()].falseNegatives += 1
        overall.falseNegatives += 1
      }
    }

    let leaves = labels.labels.filter { $0.kind == Labels.leaveKind }
    let intrusions = result.prompts.filter { prompt in
      leaves.contains { utterancesBetween($0.at, prompt.at) == 0 && $0.at <= prompt.at }
    }.count

    return EvalReport(byKind: byKind, overall: overall, finished: finished, intrusions: intrusions)
  }
}

extension EvalReport {
  public var summary: String {
    func line(_ name: String, _ kind: Kind) -> String {
      let p = kind.precision.map { String(format: "%.2f", $0) } ?? "-"
      let r = kind.recall.map { String(format: "%.2f", $0) } ?? "-"
      let l = kind.medianLateness.map { String(format: "%.1f", $0) } ?? "-"
      return "\(name.padding(toLength: 10, withPad: " ", startingAt: 0)) p \(p)  r \(r)  late \(l)"
    }
    var out = [line("overall", overall), line("finished", finished)]
    for (name, kind) in byKind.sorted(by: { $0.key < $1.key }) {
      out.append(line(name, kind))
    }
    out.append("intrusions \(intrusions)")
    return out.joined(separator: "\n")
  }
}
