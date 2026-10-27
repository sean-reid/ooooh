import Foundation
import Session

/// One grid point's merged report per recorded run, and the worst run's numbers.
struct SweepRow {
  var label: String
  var reports: [EvalReport]

  var minPrecision: Double { reports.map { $0.overall.precision ?? 0 }.min() ?? 0 }
  var minRecall: Double { reports.map { $0.overall.recall ?? 0 }.min() ?? 0 }
  var maxIntrusions: Int { reports.map(\.intrusions).max() ?? 0 }
  var maxCollisions: Int { reports.map(\.collisions).max() ?? 0 }

  func clears(_ floor: Double) -> Bool { minRecall >= floor }

  /// Points that clear the floor on every run come first, by their lowest precision, then by recall.
  func ranksAbove(_ other: SweepRow, floor: Double) -> Bool {
    if clears(floor) != other.clears(floor) { return clears(floor) }
    if minPrecision != other.minPrecision { return minPrecision > other.minPrecision }
    return minRecall > other.minRecall
  }

  func line(floor: Double, labelWidth: Int) -> String {
    let runs = reports.map { report in
      String(
        format: "%.2f/%.2f", report.overall.precision ?? 0, report.overall.recall ?? 0)
    }.joined(separator: "  ")
    let mark = clears(floor) ? " " : "!"
    return String(
      format: "%@ %@ | %@ | min %.2f/%.2f  intr %d  coll %d", mark,
      label.padding(toLength: labelWidth, withPad: " ", startingAt: 0), runs, minPrecision,
      minRecall,
      maxIntrusions, maxCollisions)
  }
}
