import Foundation

/// Bounds a merged report has to stay inside: rates are floors, counts are caps.
public struct EvalGate: Equatable, Sendable {
  public var precision: Double?
  public var recall: Double?
  public var finishedRecall: Double?
  public var intrusions: Int?
  public var collisions: Int?

  public enum SpecError: Error, Equatable {
    case unknownKey(String)
    case badValue(String)
  }

  public init(
    precision: Double? = nil, recall: Double? = nil, finishedRecall: Double? = nil,
    intrusions: Int? = nil, collisions: Int? = nil
  ) {
    self.precision = precision
    self.recall = recall
    self.finishedRecall = finishedRecall
    self.intrusions = intrusions
    self.collisions = collisions
  }

  /// `precision=0.28,recall=0.45,finished-recall=0.55,intrusions=3,collisions=14`, any subset.
  public init(spec: String) throws {
    for part in spec.split(separator: ",") {
      let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
      guard pair.count == 2 else { throw SpecError.badValue(String(part)) }
      switch pair[0] {
      case "precision": precision = try Self.rate(pair[1])
      case "recall": recall = try Self.rate(pair[1])
      case "finished-recall": finishedRecall = try Self.rate(pair[1])
      case "intrusions": intrusions = try Self.count(pair[1])
      case "collisions": collisions = try Self.count(pair[1])
      default: throw SpecError.unknownKey(pair[0])
      }
    }
  }

  static func rate(_ text: String) throws -> Double {
    guard let value = Double(text), (0...1).contains(value) else {
      throw SpecError.badValue(text)
    }
    return value
  }

  static func count(_ text: String) throws -> Int {
    guard let value = Int(text), value >= 0 else { throw SpecError.badValue(text) }
    return value
  }

  /// One line per bound the report crosses, empty when it passes. A rate with no denominator counts as 0.
  public func failures(_ report: EvalReport) -> [String] {
    var out: [String] = []
    func floor(_ name: String, _ value: Double?, _ bound: Double?) {
      guard let bound, (value ?? 0) < bound else { return }
      out.append(String(format: "%@ %.2f is under the %.2f floor", name, value ?? 0, bound))
    }
    func cap(_ name: String, _ value: Int, _ bound: Int?) {
      guard let bound, value > bound else { return }
      out.append("\(name) \(value) is over the cap of \(bound)")
    }
    floor("precision", report.overall.precision, precision)
    floor("recall", report.overall.recall, recall)
    floor("finished recall", report.finished.recall, finishedRecall)
    cap("intrusions", report.intrusions, intrusions)
    cap("collisions", report.collisions, collisions)
    return out
  }
}
