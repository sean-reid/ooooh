import Foundation
import Governor
import Proxy
import Session
import Transcription

// eval <fixture.json> <labels.json> [--config c.json] [--answers a.jsonl]
// eval --corpus <dir> [--config c.json] [--answers-dir <dir>] [--require-perfect]
// eval --corpus <dir> --live <worker url> --record-dir <dir>
// Any form takes --arming-delay <seconds> to override the config's, 0 to speak at the decision.
//
// --live asks the real Jev through the Worker at every check, writes one JSON
// line per answer under --record-dir, and scores the run with the real floor.
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

let liveURL = option("--live").map { URL(string: $0)! }
let recordDir = option("--record-dir")

func evaluate(_ run: Run, config base: GovernorConfig) async throws -> EvalReport {
  var config = base
  let decisions: any DecisionProvider
  var recorder: RecordingDecisionProvider?
  if let liveURL {
    guard let recordDir else { fail("--live needs --record-dir") }
    try FileManager.default.createDirectory(
      atPath: recordDir, withIntermediateDirectories: true)
    let live = JevDecisionProvider(client: ProxyClient(baseURL: liveURL))
    let recording = try RecordingDecisionProvider(
      live, writingTo: URL(filePath: "\(recordDir)/\(run.name).jsonl"))
    recorder = recording
    decisions = recording
  } else if let answers = run.answers {
    decisions = try RecordedDecisionProvider(contentsOf: URL(filePath: answers))
  } else {
    config.floor = .init(min: 0, max: 0)
    decisions = OracleDecisionProvider(labels: run.labels)
  }
  let result = await FixtureDriver.run(
    fixture: run.fixture, config: config,
    dependencies: .init(
      decisions: decisions, compactor: PassthroughCompactor(), phraser: TemplatePhraser()))
  if args.contains("--dump") {
    dump(run, result)
  }
  if let recorder {
    try await recorder.close()
    let checks = await recorder.count
    FileHandle.standardError.write(Data("  \(run.name): \(checks) checks recorded\n".utf8))
  }
  return EvalReport.score(result, against: run.labels)
}

/// One line per check: time, answers, and whether a label sits within one utterance before it.
func dump(_ run: Run, _ result: SessionResult) {
  let ends = result.transcript.map(\.end).sorted()
  func labeled(at: TimeInterval) -> String {
    for label in run.labels.labels where label.at <= at {
      let between = ends.filter { $0 > label.at && $0 <= at }.count
      if between <= EvalReport.tolerance { return label.kind }
    }
    return "-"
  }
  for record in result.records {
    guard case .check(let at, _, let a, let decision) = record else { continue }
    let line = String(
      format: "%@ %7.1f good %.2f %@ %.2f diff %.2f mom %.2f fin %.2f cmd %@ %.2f label %@ -> %@",
      run.name, at, a.goodMoment.probability, a.intervention.choice.rawValue,
      a.intervention.confidence, a.articulationDifficulty.score, a.momentum.score,
      a.seemsFinished.probability, a.addressesApp.choice.rawValue, a.addressesApp.confidence,
      labeled(at: at), String(describing: decision))
    let cues = a.cues.sorted { $0.key < $1.key }
      .map { String(format: "%@=%.2f", $0.key, $0.value) }.joined(separator: " ")
    print(line + (cues.isEmpty ? "" : " cues " + cues))
  }
}

var config =
  try option("--config").map { try load(GovernorConfig.self, $0) } ?? .initial
if let delay = option("--arming-delay") {
  guard let seconds = TimeInterval(delay), seconds >= 0 else {
    fail("--arming-delay takes seconds, 0 or more")
  }
  config.armingDelay = seconds
}

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

let mode =
  liveURL != nil
  ? "live Jev, real floor"
  : runs.allSatisfy { $0.answers == nil } ? "oracle, floor off" : "recorded answers"
print("config v\(config.version)  arming \(config.armingDelay) s  \(mode)")

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
