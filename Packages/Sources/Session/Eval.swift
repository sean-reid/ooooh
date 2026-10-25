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
  public static let commandKinds: Set<String> = ["recall", "wrapUp"]
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

    mutating func add(_ other: Kind) {
      truePositives += other.truePositives
      falsePositives += other.falsePositives
      falseNegatives += other.falseNegatives
      latenesses += other.latenesses
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
  public var commands: Kind
  public var intrusions: Int
  /// Prompts the speaker would have talked over: the next utterance began inside the speak window.
  public var collisions: Int = 0

  /// Seconds from a decision to the end of the spoken prompt: 1.5 s to the first syllable plus about 3 s of speech.
  public static let speakWindow: TimeInterval = 4.5

  /// Precision and recall of 1 wherever a label or a decision exists.
  public var isPerfect: Bool {
    [overall, finished, commands].allSatisfy { kind in
      (kind.precision ?? 1) == 1 && (kind.recall ?? 1) == 1
    }
  }

  /// Sums the counts of several sessions into one report.
  public static func merged(_ reports: [EvalReport]) -> EvalReport {
    var out = EvalReport(
      byKind: [:], overall: Kind(), finished: Kind(), commands: Kind(), intrusions: 0)
    for report in reports {
      out.overall.add(report.overall)
      out.finished.add(report.finished)
      out.commands.add(report.commands)
      out.intrusions += report.intrusions
      for (name, kind) in report.byKind {
        out.byKind[name, default: Kind()].add(kind)
      }
    }
    return out
  }

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
    var commands = Kind()
    var unmatched = labels.labels.filter { $0.kind != Labels.leaveKind }

    func match(at: TimeInterval, kind: String?) -> (Labels.Label, Int)? {
      let candidates = unmatched.enumerated().compactMap { index, label -> (Int, Int)? in
        guard label.at <= at else { return nil }
        if let kind, label.kind != kind { return nil }
        if kind == nil,
          label.kind == Labels.finishedKind || Labels.commandKinds.contains(label.kind)
        {
          return nil
        }
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
    for command in result.commands {
      let name = command.command.rawValue
      if let (_, late) = match(at: command.at, kind: name) {
        byKind[name, default: Kind()].truePositives += 1
        byKind[name, default: Kind()].latenesses.append(late)
        commands.truePositives += 1
        commands.latenesses.append(late)
      } else {
        byKind[name, default: Kind()].falsePositives += 1
        commands.falsePositives += 1
      }
    }
    for label in unmatched {
      if label.kind == Labels.finishedKind {
        finished.falseNegatives += 1
      } else if Labels.commandKinds.contains(label.kind) {
        byKind[label.kind, default: Kind()].falseNegatives += 1
        commands.falseNegatives += 1
      } else {
        byKind[label.kind, default: Kind()].falseNegatives += 1
        overall.falseNegatives += 1
      }
    }

    let leaves = labels.labels.filter { $0.kind == Labels.leaveKind }
    let intrusions = result.prompts.filter { prompt in
      leaves.contains { utterancesBetween($0.at, prompt.at) == 0 && $0.at <= prompt.at }
    }.count
    let starts = result.transcript.map(\.start).sorted()
    let collisions = result.prompts.filter { prompt in
      guard let next = starts.first(where: { $0 > prompt.at }) else { return false }
      return next - prompt.at < speakWindow
    }.count

    return EvalReport(
      byKind: byKind, overall: overall, finished: finished, commands: commands,
      intrusions: intrusions, collisions: collisions)
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
    var out = [line("overall", overall), line("finished", finished), line("commands", commands)]
    for (name, kind) in byKind.sorted(by: { $0.key < $1.key }) {
      out.append(line(name, kind))
    }
    out.append("intrusions \(intrusions)  collisions \(collisions)")
    return out.joined(separator: "\n")
  }
}
