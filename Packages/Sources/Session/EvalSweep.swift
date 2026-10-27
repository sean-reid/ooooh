import Foundation
import Governor

/// A grid of speak bars and cue weights to replay a recording through, one config per point.
public struct EvalSweep: Equatable, Sendable {
  public struct Axis: Equatable, Sendable {
    public var name: String
    public var values: [Double]
  }

  public struct Point: Equatable, Sendable {
    public var bar: Double?
    public var weights: [String: Double]

    /// The base config with this point's bar and weights written over it.
    public func applied(to base: GovernorConfig) -> GovernorConfig {
      var config = base
      if let bar { config.speak.probability = bar }
      for (name, weight) in weights { config.cueWeights[name] = weight }
      return config
    }

    public var label: String {
      var parts = bar.map { [String(format: "bar %.2f", $0)] } ?? []
      for (name, weight) in weights.sorted(by: { $0.key < $1.key }) {
        parts.append(String(format: "%@ %g", name, weight))
      }
      return parts.joined(separator: "  ")
    }
  }

  public enum SpecError: Error, Equatable {
    case badValue(String)
    case emptyAxis(String)
  }

  public var bars: [Double]
  public var weights: [Axis]

  /// `bar=0.8,0.85,0.9;trailsOff=1,1.2,1.38;hangingQuestion=0,1`. `bar` is the speak
  /// probability; any other name is a cue weight. Each axis takes one or more values.
  public init(spec: String) throws {
    bars = []
    weights = []
    for axis in spec.split(separator: ";") {
      let pair = axis.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        .map(String.init)
      guard pair.count == 2 else { throw SpecError.badValue(String(axis)) }
      let values = try pair[1].split(separator: ",").map { text -> Double in
        guard let value = Double(text), value >= 0 else { throw SpecError.badValue(String(text)) }
        return value
      }
      guard !values.isEmpty else { throw SpecError.emptyAxis(pair[0]) }
      if pair[0] == "bar" {
        bars = values
      } else {
        weights.append(Axis(name: pair[0], values: values))
      }
    }
  }

  /// Every combination, bars outermost, in the order the spec listed the axes.
  public var points: [Point] {
    var out = (bars.isEmpty ? [nil] : bars.map(Optional.some)).map {
      Point(bar: $0, weights: [:])
    }
    for axis in weights {
      out = out.flatMap { point in
        axis.values.map { value in
          var next = point
          next.weights[axis.name] = value
          return next
        }
      }
    }
    return out
  }
}
