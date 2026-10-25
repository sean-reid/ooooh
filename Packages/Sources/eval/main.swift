import Foundation
import Governor
import Session
import Transcription

// eval <fixture.json> <labels.json> [--config c.json] [--answers a.jsonl]
// eval --corpus <dir> [--config c.json] [--answers-dir <dir>] [--require-perfect]
//
// Without answers the oracle runs with the floor off, so the loop and the scorer
// are checked against each other and a session must score 1.00 everywhere.

let args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
  guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
  return args[index + 1]
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(2)
}

let decoder = JSONDecoder()

func load<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
  try decoder.decode(type, from: Data(contentsOf: URL(filePath: path)))
}

struct Run {
  var name: String
  var fixture: FixtureTranscriber.Fixture
  var labels: Labels
  var answers: String?
}

/// Pairs every fixture in a directory with its labels file.
func corpus(in directory: String, answersDir: String?) throws -> [Run] {
  let files = try FileManager.default.contentsOfDirectory(atPath: directory)
  return try files.sorted().compactMap { file -> Run? in
    guard file.hasSuffix(".json"), !file.hasSuffix(".labels.json") else { return nil }
    var name = String(file.dropLast(".json".count))
    if name.hasSuffix(".fixture") { name = String(name.dropLast(".fixture".count)) }
    let labelsPath = "\(directory)/\(name).labels.json"
    guard FileManager.default.fileExists(atPath: labelsPath) else { return nil }
    let answers = answersDir.map { "\($0)/\(name).jsonl" }
    return Run(
      name: name,
      fixture: try load(FixtureTranscriber.Fixture.self, "\(directory)/\(file)"),
      labels: try load(Labels.self, labelsPath),
      answers: answers.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil })
  }
}

func evaluate(_ run: Run, config base: GovernorConfig) async throws -> EvalReport {
  var config = base
  let decisions: any DecisionProvider
  if let answers = run.answers {
    decisions = try RecordedDecisionProvider(contentsOf: URL(filePath: answers))
  } else {
    config.floor = .init(min: 0, max: 0)
    decisions = OracleDecisionProvider(labels: run.labels)
  }
  let result = await FixtureDriver.run(
    fixture: run.fixture, config: config,
    dependencies: .init(
      decisions: decisions, compactor: PassthroughCompactor(), phraser: TemplatePhraser()))
  return EvalReport.score(result, against: run.labels)
}

let config =
  try option("--config").map { try load(GovernorConfig.self, $0) } ?? .initial

var runs: [Run]
if let directory = option("--corpus") {
  runs = try corpus(in: directory, answersDir: option("--answers-dir"))
  guard !runs.isEmpty else { fail("no fixture and labels pairs in \(directory)") }
} else {
  guard args.count >= 2, !args[0].hasPrefix("--") else {
    fail("usage: eval <fixture.json> <labels.json> [--config c.json] [--answers a.jsonl]")
  }
  runs = [
    Run(
      name: URL(filePath: args[0]).deletingPathExtension().lastPathComponent,
      fixture: try load(FixtureTranscriber.Fixture.self, args[0]),
      labels: try load(Labels.self, args[1]),
      answers: option("--answers"))
  ]
}

let mode = runs.allSatisfy { $0.answers == nil } ? "oracle, floor off" : "recorded answers"
print("config v\(config.version)  \(mode)")

var reports: [EvalReport] = []
for run in runs {
  let report = try await evaluate(run, config: config)
  reports.append(report)
  if runs.count > 1 {
    let p = report.overall.precision.map { String(format: "%.2f", $0) } ?? "-"
    let r = report.overall.recall.map { String(format: "%.2f", $0) } ?? "-"
    let mark = report.isPerfect ? " " : "!"
    print("\(mark) \(run.name.padding(toLength: 20, withPad: " ", startingAt: 0)) p \(p)  r \(r)")
  }
}

let combined = EvalReport.merged(reports)
if runs.count > 1 { print("") }
print(combined.summary)

if args.contains("--require-perfect"), !reports.allSatisfy(\.isPerfect) {
  fail("oracle did not score 1.00 on every session")
}
