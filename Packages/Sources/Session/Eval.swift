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

  /// What the scorer would make of a prompt at `at`.
  public enum Expectation: Equatable, Sendable {
    case speak(kind: String)
    case leave
    case finished
    case wait

    public var name: String {
      switch self {
      case .speak: "speak"
      case .leave: "leave"
      case .finished: "finished"
      case .wait: "wait"
      }
    }

    public var kind: String? {
      if case .speak(let kind) = self { kind } else { nil }
    }
  }

  /// A moment label within tolerance wins, then a leave window, then a finished label within
  /// tolerance. A command label is not a moment to speak, so it reads as wait.
  public func expectation(at: TimeInterval, ends: UtteranceEnds) -> Expectation {
    let within = labels.compactMap { label in
      ends.lateness(of: label, at: at).map { (label, $0) }
    }
    let moments = within.filter {
      $0.0.kind != Self.leaveKind && $0.0.kind != Self.finishedKind
        && !Self.commandKinds.contains($0.0.kind)
    }
    if let moment = moments.min(by: { $0.1 < $1.1 }) { return .speak(kind: moment.0.kind) }
    if labels.contains(where: { $0.kind == Self.leaveKind && ends.inside($0, at: at) }) {
      return .leave
    }
    if within.contains(where: { $0.0.kind == Labels.finishedKind }) { return .finished }
    return .wait
  }
}

/// The utterance ends of a session, so lateness is counted one way wherever a label meets a time.
public struct UtteranceEnds: Equatable, Sendable {
  let ends: [TimeInterval]

  public init(_ transcript: [Segment]) {
    ends = transcript.map(\.end).sorted()
  }

  public func count(after from: TimeInterval, through to: TimeInterval) -> Int {
    ends.filter { $0 > from && $0 <= to }.count
  }

  /// Utterances from the label to `at`, nil when the label comes later or is past the tolerance.
  public func lateness(of label: Labels.Label, at: TimeInterval) -> Int? {
    guard label.at <= at else { return nil }
    let late = count(after: label.at, through: at)
    return late <= EvalReport.tolerance ? late : nil
  }

  /// Whether `at` is still inside the utterance the label marks.
  public func inside(_ label: Labels.Label, at: TimeInterval) -> Bool {
    label.at <= at && count(after: label.at, through: at) == 0
  }
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
  /// Decisions that armed and were cut short by speech before they spoke.
  public var cancelled: Int = 0

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
      out.collisions += report.collisions
      out.cancelled += report.cancelled
      for (name, kind) in report.byKind {
        out.byKind[name, default: Kind()].add(kind)
      }
    }
    return out
  }

  /// How many utterances late a decision may land and still count.
  public static let tolerance = 1

  public static func score(_ result: SessionResult, against labels: Labels) -> EvalReport {
    let ends = UtteranceEnds(result.transcript)

    var byKind: [String: Kind] = [:]
    var overall = Kind()
    var finished = Kind()
    var commands = Kind()
    var unmatched = labels.labels.filter { $0.kind != Labels.leaveKind }

    func match(at: TimeInterval, kind: String?) -> (Labels.Label, Int)? {
      let candidates = unmatched.enumerated().compactMap { index, label -> (Int, Int)? in
        if let kind, label.kind != kind { return nil }
        if kind == nil,
          label.kind == Labels.finishedKind || Labels.commandKinds.contains(label.kind)
        {
          return nil
        }
        return ends.lateness(of: label, at: at).map { (index, $0) }
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
      leaves.contains { ends.inside($0, at: prompt.at) }
    }.count
    let starts = result.transcript.map(\.start).sorted()
    let collisions = result.spokenDecisions.filter { decidedAt in
      guard let next = starts.first(where: { $0 > decidedAt }) else { return false }
      return next - decidedAt < speakWindow
    }.count

    return EvalReport(
      byKind: byKind, overall: overall, finished: finished, commands: commands,
      intrusions: intrusions, collisions: collisions, cancelled: result.cancelledArms.count)
  }
}

extension SessionResult {
  /// When each spoken prompt was decided: the arm when it had one, else the prompt itself.
  var spokenDecisions: [TimeInterval] {
    var armed: TimeInterval?
    var out: [TimeInterval] = []
    for record in records {
      switch record {
      case .promptArmed(let at, .intervention): armed = at
      case .promptArmed(_, .finishedQuestion), .promptCancelled: armed = nil
      case .prompt(let at, _, _):
        out.append(armed ?? at)
        armed = nil
      default: break
      }
    }
    return out
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
    out.append("intrusions \(intrusions)  collisions \(collisions)  cancelled \(cancelled)")
    return out.joined(separator: "\n")
  }
}
